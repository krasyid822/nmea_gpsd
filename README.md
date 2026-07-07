Linux:
<img width="1278" height="752" alt="image" src="https://github.com/user-attachments/assets/130dd640-0822-4ea5-add5-a078946c74e0" />
Android:
<img width="434" height="935" alt="image" src="https://github.com/user-attachments/assets/56447ffb-873d-4d46-a90e-364ff6e670d2" />

# nmea_gpsd

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## How to use?

Berikut adalah panduan lengkap cara menggunakan tool ini untuk mengirimkan koordinat GPS dari HP Android Anda ke `gpsd` di Linux CachyOS:

---

### Langkah 1: Jalankan Aplikasi di Android
1. Hubungkan HP Android ke komputer menggunakan kabel USB dan pastikan **USB Debugging** sudah aktif.
2. Jalankan perintah berikut di terminal VS Code/workspace untuk menginstal dan menjalankan aplikasi ke HP Android Anda:
   ```bash
   flutter run
   ```
3. Izinkan aplikasi mengakses lokasi (**Location Permission**) saat diminta di layar HP Anda.

---

### Langkah 2: Siapkan `gpsd` di CachyOS Linux
Buka terminal baru di komputer CachyOS Anda, lalu jalankan `gpsd` agar mendengarkan (listen) data GPS via protokol **UDP** pada port tertentu (misalnya port `9999`):

```bash
sudo gpsd -N -D 2 udp://*:9999
```
* **`-N`**: Menjalankan `gpsd` di foreground (agar Anda bisa melihat log langsung di terminal).
* **`-D 2`**: Menampilkan level debug info.
* **`udp://*:9999`**: Memberitahu `gpsd` untuk menerima input NMEA dari port UDP `9999` dari perangkat mana pun di jaringan lokal.

---

### Langkah 3: Mulai Hubungkan dari Aplikasi
1. Cari tahu **IP Address lokal** komputer Linux CachyOS Anda (bisa cek menggunakan perintah `ip a` atau `ifconfig` di Linux). Contoh IP lokal: `192.168.1.15`.
2. Di aplikasi Android, masukkan pengaturan berikut:
   * **Host IP**: Isi dengan IP komputer Linux CachyOS Anda (misal: `192.168.1.15`).
   * **Port**: `9999`
   * **Protocol**: Pilih **UDP**.
3. Ketuk tombol **START STREAMING**.
4. Anda akan melihat log NMEA (`$GPRMC` dan `$GPGGA`) mulai terkirim secara berkala di kolom *Log* aplikasi.

---

### Langkah 4: Verifikasi di CachyOS
Buka terminal baru di komputer Linux CachyOS Anda, lalu jalankan salah satu perintah berikut untuk memverifikasi apakah data GPS sudah masuk dan berhasil dibaca oleh `gpsd`:

* Menggunakan **`cgps`** (tampilan minimalis):
  ```bash
  cgps
  ```
* Menggunakan **`gpsmon`** (tampilan monitor real-time lengkap):
  ```bash
  gpsmon
  ```

Jika berhasil, Anda akan melihat informasi lintang (latitude), bujur (longitude), kecepatan, arah, dan waktu terupdate secara real-time sesuai lokasi HP Android Anda!

---

## Cara Menggunakan Versi Linux (Sebagai Bridge Receiver)

Jika Anda tidak ingin mengonfigurasi port UDP `gpsd` secara langsung, Anda bisa menggunakan aplikasi ini di Linux CachyOS sebagai **Bridge Receiver**. 

### Alur Kerja:
`[HP Android] -> (UDP 9999) -> [Aplikasi Linux (Bridge)] -> (TCP 8888) -> [gpsd]`

### Langkah 1: Jalankan Aplikasi di Linux
1. Jalankan aplikasi di Linux desktop Anda dengan perintah:
   ```bash
   flutter run -d linux
   ```
2. Aplikasi akan mendeteksi OS Linux secara otomatis dan menampilkan **Interface Bridge Server**.
3. Tentukan port yang ingin Anda gunakan (default: UDP `9999` untuk menerima data dari Android, dan TCP `8888` untuk dihubungkan ke `gpsd`).
4. Klik tombol **START BRIDGE SERVER**.

### Langkah 2: Hubungkan gpsd ke Bridge
Jalankan `gpsd` di terminal Linux Anda dengan mengarahkannya ke port TCP Bridge:
```bash
sudo gpsd -N -n tcp://localhost:8888
```

### Langkah 3: Kirim Data dari Android
1. Jalankan aplikasi di Android.
2. Masukkan **Linux Host IP** (IP komputer Anda) dan Port **9999** (UDP).
3. Klik **START STREAMING**.
4. Anda akan melihat log data GPS dari Android masuk ke aplikasi Linux dan langsung diteruskan ke `gpsd`.

### Langkah 4: Verifikasi di Linux
Jalankan `cgps` atau `gpsmon` di terminal Linux Anda untuk melihat data GPS yang terupdate.

## Build
### Linux
```fish
flutter build linux --release
```
### Android
```fish
flutter build apk --release
```

## Catatan
Host IP di android adalah ip komputer
