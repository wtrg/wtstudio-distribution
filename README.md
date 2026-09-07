# WT Studio - Video Vietnamese Localization Tool

**Current release: v2.0.18**

## Cài đặt nhanh (1 lệnh duy nhất)

### PowerShell:
```powershell
irm "https://raw.githubusercontent.com/wtrg/wtstudio-distribution/main/install.ps1" | iex
```

### CMD:
```cmd
powershell -Command "irm 'https://raw.githubusercontent.com/wtrg/wtstudio-distribution/main/install.ps1' | iex"
```

Nếu muốn server local tự khởi động nền cùng Windows (không tự mở trình duyệt),
chạy lệnh sau:

```powershell
$installer = Join-Path $env:TEMP "wtstudio-install.ps1"
irm "https://raw.githubusercontent.com/wtrg/wtstudio-distribution/main/install.ps1" -OutFile $installer
powershell.exe -ExecutionPolicy Bypass -File $installer -EnableStartup
```

---

## Sau khi cài đặt:

**Mở PowerShell/CMD mới và gõ:**
```powershell
vietdub-processor
```

Website ViệtDub sẽ kết nối tới bộ xử lý local trên `127.0.0.1:8765`.

Khi bật `-EnableStartup`, WTStudio chỉ khởi động server nền; người dùng mở web
khi cần. Có thể tắt bằng cách xóa shortcut `WT Studio (background).lnk` trong
thư mục Startup của Windows.

---

## Cài đặt thủ công:

1. Tải ZIP mới nhất tại [GitHub Releases](https://github.com/wtrg/wtstudio-distribution/releases)
2. Giải nén vào thư mục bất kỳ
3. Chạy `wtstudio.exe`
4. `wtstudio.exe` tự mở trình duyệt trên cổng loopback khả dụng.

---

## Yêu cầu:

- Windows 10/11 64-bit
- 4GB RAM (khuyến nghị 8GB)
- Kết nối Internet để Edge-TTS tạo giọng trực tuyến
- FFmpeg được đóng gói trong processor
- NVIDIA GPU không bắt buộc cho Edge-TTS

---

## Hỗ trợ:

- GitHub Releases: https://github.com/wtrg/wtstudio-distribution/releases
- Email: support@example.com

## Gỡ cài đặt:

Đóng WTStudio, xóa shortcut trên Desktop và shortcut trong thư mục Startup (nếu
đã bật), sau đó xóa thư mục cài đặt mặc định:

```powershell
Remove-Item -LiteralPath "$env:LOCALAPPDATA\WTStudio" -Recurse -Force
```

Nếu muốn dọn PATH, xóa riêng đường dẫn `WTStudio` khỏi biến môi trường User.

---

## Lưu ý:

- Edge-TTS không cần tải model TTS nặng.
- Processor mới được cài bổ sung vào thư mục WTStudio hiện có và không xóa project/user data.
