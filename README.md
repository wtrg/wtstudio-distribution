# WTStudio — Công cụ Việt hóa video

WTStudio hỗ trợ tải video, nhận diện lời nói, dịch, lồng tiếng và xuất video
trên máy local.

## Cài nhanh trên Windows

Mở PowerShell:

```powershell
irm "https://raw.githubusercontent.com/tranvantruonguser-cmd/wtrg-dis-2/main/install.ps1" | iex
```

Mở PowerShell/CMD mới rồi chạy:

```powershell
wtstudio
```

Nếu muốn chạy từng bước trong PowerShell:

```powershell
$installer = Join-Path $env:TEMP "wtstudio-install.ps1"
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/tranvantruonguser-cmd/wtrg-dis-2/main/install.ps1" -OutFile $installer
powershell.exe -ExecutionPolicy Bypass -File $installer
```

Hoặc mở Command Prompt (CMD):

```cmd
curl.exe -L "https://raw.githubusercontent.com/tranvantruonguser-cmd/wtrg-dis-2/main/install.ps1" -o "%TEMP%\wtstudio-install.ps1"
powershell.exe -ExecutionPolicy Bypass -File "%TEMP%\wtstudio-install.ps1"
```

Sau khi cài xong, đóng và mở lại PowerShell/CMD rồi chạy `wtstudio`.

## Chạy từ source trên Windows, macOS hoặc Linux

Yêu cầu Git, Python 3.10+, Node.js/npm, FFmpeg và `uv`:

```bash
git clone https://github.com/wtrg/wtstudio-source.git
cd wtstudio-source
uv sync --python 3.10
cd studio_web && npm install && npm run build
cd .. && uv run python wtstudio.py
```

## Mua license key

Liên hệ bot Telegram: [@wtstudio_shop_bot](https://t.me/wtstudio_shop_bot).

Nếu thanh toán xong nhưng chưa nhận key, dùng `/orders` rồi `/licenses` trong
bot; nếu mua ẩn danh trên web, mở claim link trên trang thanh toán.

## Tải bản phát hành

[GitHub Releases](https://github.com/tranvantruonguser-cmd/wtrg-dis-2/releases)

Xem thêm file [HUONG_DAN_CAI_DAT.txt](HUONG_DAN_CAI_DAT.txt) trong source để
biết cách dùng Docker và kích hoạt license.

## Yêu cầu tối thiểu

- Windows 10/11 64-bit, macOS hoặc Linux
- RAM 4 GB (khuyến nghị 8 GB+)
- Internet cho lần đầu tải model
- GPU NVIDIA/CUDA là tùy chọn
