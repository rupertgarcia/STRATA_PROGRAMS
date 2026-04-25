import os
import time
import struct
import socket
import serial
import sqlite3
import datetime

# --- Configuration ---
DB_PATH = 'soil_data.db'
SERIAL_PORT = '/dev/ttyUSB0'
BAUD_RATE = 9600

def init_db():
    conn = sqlite3.connect(DB_PATH, check_same_thread=False)
    cursor = conn.cursor()
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS sensor_readings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
            crop_name TEXT,
            temperature REAL,
            moisture REAL,
            ec REAL,
            ph REAL,
            nitrogen REAL,
            phosphorus REAL,
            potassium REAL
        )
    ''')
    conn.commit()
    return conn

def calculate_crc16(data: bytes) -> bytes:
    crc = 0xFFFF
    for pos in data:
        crc ^= pos
        for _ in range(8):
            if (crc & 1) != 0:
                crc >>= 1
                crc ^= 0xA001
            else:
                crc >>= 1
    return struct.pack('<H', crc)

def read_sensor_data(ser):
    # Modbus RTU Read Holding Registers (Function Code 3)
    # Target Slave ID: 1, Starting Address: 0x0000, Length: 7 registers
    request = bytes([0x01, 0x03, 0x00, 0x00, 0x00, 0x07])
    request += calculate_crc16(request)
    
    try:
        ser.reset_input_buffer()
        ser.write(request)
        time.sleep(0.1)  # Minimal wait for response
        
        # Expected Response: ID(1) + FC(1) + ByteCount(1) + Data(14) + CRC(2) = 19 bytes
        response = ser.read(19)
        
        if len(response) == 19:
            # Check CRC
            if calculate_crc16(response[:-2]) == response[-2:]:
                # Data mapping: 
                # 0: Moisture (Unsigned Short, >H)
                # 1: Temperature (Signed Short, >h) - allows negative temps
                # 2: EC (Unsigned Short, >H)
                # 3: pH (Unsigned Short, >H)
                # 4: Nitrogen (Unsigned Short, >H)
                # 5: Phosphorus (Unsigned Short, >H)
                # 6: Potassium (Unsigned Short, >H)
                data = struct.unpack('>HhHHHHH', response[3:17])
                
                moisture = data[0] / 10.0
                temperature = data[1] / 10.0
                ec = data[2]
                ph = data[3] / 10.0
                n = data[4]
                p = data[5]
                k = data[6]
                
                return (moisture, temperature, ec, ph, n, p, k)
            else:
                print("[Warning] Sensor read error: CRC Mismatch")
        else:
            if len(response) > 0:
                print(f"[Warning] Sensor read error: Incomplete frame ({len(response)} bytes)")
    except Exception as e:
        print(f"[Error] Serial communication interrupted: {e}")
        
    return None

def perform_scan(client, ser, conn, crop_name):
    print(f"[{datetime.datetime.now()}] Commencing 60s scan for Crop: {crop_name}")
    
    for iteration in range(6):
        readings = []
        for sample in range(10):
            val = read_sensor_data(ser)
            if val is not None:
                readings.append(val)
            # Sample exactly once roughly every 1 second
            time.sleep(0.9) 
            
        if not readings:
            print(f"[Warning] Iteration {iteration+1}/6 failed: No valid sensor readings.")
            continue
            
        # Calculate mathematical average for the 7 parameters
        avg_vals = []
        for i in range(7):
            summ = sum(r[i] for r in readings)
            avg = summ / len(readings)
            avg_vals.append(round(avg, 2))
            
        m, t, ec, ph, n, p, k = avg_vals
        
        # Store averaged values into SQLite3
        cursor = conn.cursor()
        cursor.execute('''
            INSERT INTO sensor_readings (crop_name, temperature, moisture, ec, ph, nitrogen, phosphorus, potassium)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ''', (crop_name, t, m, ec, ph, n, p, k))
        conn.commit()
        
        print(f"[{datetime.datetime.now()}] Iteration {iteration+1}/6 - Logged | T:{t}°C, H:{m}%, EC:{ec}, pH:{ph}, N:{n}, P:{p}, K:{k}")

    # Signal completion to application
    print("Sending final 'Scan finished' message...")
    try:
        client.send("Scan finished\n".encode("utf-8"))
    except Exception as e:
        print(f"[Error] Failed to send completion message: {e}")

def handle_client(client, ser, conn):
    while True:
        try:
            print("\nWaiting for app command (expected: '{Crop_Name},Start_Scan')...")
            # Usually simple string sends; handling max 1024 bytes buffer
            data = client.recv(1024).decode("utf-8").strip()
            
            if not data:
                # Empty message often means disconnection
                print("Client disconnected.")
                break
                
            print(f"Received payload: '{data}'")
            
            # Check for trigger mechanism
            if "Start_Scan" in data or "Start Scan" in data:
                parts = data.split(',')
                crop_name = parts[0].strip() if len(parts) > 1 else "Unknown_Crop"
                
                # Initiate 60s logging workflow
                perform_scan(client, ser, conn, crop_name)
                
                # Enter post-scan waiting logic
                print("\nWaiting for post-scan commands...")
                while True:
                    cmd_data = client.recv(1024).decode("utf-8").strip()
                    if not cmd_data:
                        print("Client disconnected during post-scan.")
                        return
                        
                    print(f"Post-Scan payload received: '{cmd_data}'")
                    
                    if "Scan Again" in cmd_data:
                        print("Resetting state for next scan.")
                        break # Break post-scan loop -> goes back to top-level command wait

                    elif "Shut Down" in cmd_data:
                        print("Instructing Raspberry Pi to shut down...")
                        try:
                            client.send("Shutting down the system...\n".encode('utf-8'))
                        except:
                            pass
                        os.system("sudo shutdown -h now")
                        return # Exit thread

                    else:
                        print("Unrecognized post-scan command. Still waiting...")
                        
        except ConnectionResetError:
            print("Bluetooth client connection forcibly closed.")
            break
        except Exception as e:
            print(f"Error handling client request: {e}")
            break

def main():
    print("--- 7-in-1 Soil Sensor Data Logger Init ---")
    
    # Initialize the local Database
    conn = init_db()
    print("SQLite database setup complete.")
    
    # Initialize RS485 communication
    try:
        ser = serial.Serial(SERIAL_PORT, BAUD_RATE, timeout=1)
        print(f"Successfully bound to Serial interface {SERIAL_PORT} @ {BAUD_RATE} baud.")
    except Exception as e:
        print(f"[Critical Error] Failed to open RS485 serial port: {e}")
        return

    # Initialize Bluetooth SPP RFCOMM Server natively via socket (only supported on Linux/Raspberry Pi)
    try:
        server_sock = socket.socket(socket.AF_BLUETOOTH, socket.SOCK_STREAM, socket.BTPROTO_RFCOMM)
        server_sock.bind(("", 1)) # Bind to ANY address on RFCOMM channel 1
        server_sock.listen(1)
        print("Bluetooth RFCOMM SPP Server initialized on Channel 1.")
    except AttributeError:
        print("[Error] AF_BLUETOOTH not available in this Python build. Ensure you are running this natively on the Raspberry Pi.")
        return
    except Exception as e:
        print(f"[Critical Error] Bluetooth initialization failed: {e}")
        return

    # Enter main loop
    try:
        while True:
            print("\nWaiting for Bluetooth pairing/connection...")
            client_sock, address = server_sock.accept()
            print(f"Bluetooth connection established with {address}")
            
            handle_client(client_sock, ser, conn)
            
            # Close stray client socket
            client_sock.close()
            
    except KeyboardInterrupt:
        print("\nManual termination signal received.")
    except Exception as e:
        print(f"\n[Fatal Error] Main loop crash: {e}")
    finally:
        print("Cleaning up resources...")
        server_sock.close()
        ser.close()
        conn.close()
        print("Shutdown complete.")

if __name__ == '__main__':
    main()
