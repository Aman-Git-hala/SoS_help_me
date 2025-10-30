# Our application is live
## download link(for ANDROID only) https://github.com/Aman-Git-hala/SoS_help_me/releases/download/Final_Release/app-release.apk
## OR Download the apk from the right side release in the repository

# Works without the internet, with bluetooth using P2P mesh

### Understanding the UI of our app

#### 1. Sending a distress call in a disaster
<p align="center">
  <img width="248" height="502" alt="image" src="https://github.com/user-attachments/assets/30c57acf-7969-4fb9-99ce-7e59f2a1ebc8" />
</p>
Here it is seen that, with the extremely lightweight signal, various combinations could be sent.

#### 2. Recieveing a distress call if someone nearby is in danger
<p align="center">
 <img width="242" height="468" alt="image" src="https://github.com/user-attachments/assets/f6df692a-17b4-4490-b111-95c7406e7322" />
</p>
As it is seen here, we have recieved a distress call with location available with google map link, and bluetooth distress
with signal strength.

#### 3. Direct link to latitude and longitude on google maps
<p align="center">
  <img width="480" height="487" alt="image" src="https://github.com/user-attachments/assets/4aa929c4-f28b-4ba3-83b4-82cb51ef5763" />
  <img width="241" height="513" alt="image" src="https://github.com/user-attachments/assets/12bbe9ae-969d-4f8e-b403-1335ec69e55a" />
</p>

---

## Core Features & Technical Details

Here is a deeper look at what the app is doing under the hood.

### Features
* **100% Offline P2P Alerts:** Works in airplane mode by broadcasting Bluetooth (BLE) packets.
* **Multi-Alert Broadcasts:** Send distinct alerts for **SOS**, **Medical Aid**, or **Trapped**.
* **Live GPS Location:** Every alert packet is encoded with the sender's live GPS coordinates.
* **"Live Ping" List:** A real-time list of all nearby alerts, which updates as new signals are received.
* **"Proximity Sensor" (RSSI):** A color-coded badge (**[STRONG]**, **[MEDIUM]**, **[WEAK]**) based on real-time signal strength (RSSI), plus the raw `dBm` value.
* **"Private Flare" UI:** A "Rescuer-Only (Encrypted)" switch to demonstrate a key real-world feature.
* **Pulsing "Live" Indicator:** A polished, red-light animation shows the user when they are actively broadcasting.

### How It Works (The "Ears" & "Mouth")
We're not pairing phones. We are using **BLE Advertising Packets**—tiny, low-power signals that we pack with data.

* **1. The "Mouth" (Broadcasting an Alert)**
    * **Package:** `flutter_ble_peripheral`
    * We fetch the **GPS location** (`geolocator`).
    * We pack this data into a tiny **13-byte packet**:
        * `[Type (1 byte)]` - e.g., 0x02 for "Medical"
        * `[Packet ID (4 bytes)]` - A random ID
        * `[Latitude (4 bytes)]` - A compressed double
        * `[Longitude (4 bytes)]` - A compressed double
    * The app **broadcasts** this packet as BLE "manufacturer data" for 10 seconds.

* **2. The "Ears" (Scanning for Alerts)**
    * **Package:** `flutter_blue_plus`
    * The app **constantly scans** for BLE packets.
    * It filters for our app's unique "company ID" (`0x1234`).
    * When it "hears" a packet, it **decodes** the 13 bytes, extracts the GPS data and alert type, and updates the "Received Alerts" UI.

### Tech Stack
* **Flutter** (Dart)
* **`flutter_blue_plus`** (BLE Scanning / "Ears")
* **`flutter_ble_peripheral`** (BLE Advertising / "Mouth")
* **`geolocator`** (GPS Location)
* **`permission_handler`** (Robust Permissions)
* **`url_launcher`** ("Open in Maps")

### Future Work
We've successfully built the P2P alert system. The next and final step is to implement the **"Flood Mesh."**
* **The Logic:** This involves adding a "Time To Live" (TTL) byte to our packet. When any phone's "Ears" hear a packet with a `TTL > 0`, it will immediately use its "Mouth" to re-broadcast that same packet with a `TTL - 1`.
* **The Result:** This allows a single SOS to "hop" from phone to phone, covering a massive area far beyond a single device's range.
