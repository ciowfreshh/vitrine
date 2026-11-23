# Spotify SYNA Beta.17

Bản này dựa trên tag upstream `v1.0.0-beta.17` ở commit `13c48337aa4def4eb1f38e389d15dc6848d848e2`. Workflow Spotify SYNA Beta.17 kiểm tra source trên macOS và tạo `Spotify_SYNA_Beta17.ipa` từ Spotify 9.1.90. IPA cần được ký bằng chứng chỉ tương thích với cách cài của bạn.

## Thư viện lời bài hát

Mở **Cài đặt Vitrine → Thư viện lời bài hát**, chạm nút menu rồi chọn **Quét Bài hát đã thích**. Thư viện ghi trên thiết bị sau từng bài. Quét tiếp đọc lại danh sách của tài khoản hiện tại, giữ các bài đã có lời và thử lại những bài chưa có lời.

Để tải cả lời khi quét, đặt **Nguồn lời được cấp phép** thành địa chỉ HTTPS của một kho mà bạn có quyền tải, lưu và xuất lời. Kho cần trả JSON của từng bài tại `<địa-chỉ>/<trackId>.json`, hoặc trả HTTP 404/204 nếu bài chưa có lời. Nguồn này nhận định danh bài, còn phiên đăng nhập Spotify chỉ được dùng với máy chủ Spotify để quét thông tin bài. Bạn cũng có thể nhập trực tiếp lời mình được phép sử dụng từ ứng dụng Tệp.

- **Chọn tất cả** chọn toàn bộ thư viện, kể cả bài ngoài bộ lọc đang mở.
- **Xuất mục đã chọn** và **Xuất tất cả** tạo ZIP gồm `manifest.json` cùng một tệp `tracks/<trackId>.json` cho từng bài. Bài thiếu lời vẫn có thông tin và trạng thái.
- Để thêm bản dịch, chỉ thêm thuộc tính `translation` vào từng dòng. Giữ nguyên `id`, `index`, `text`, `startMs` và `endMs`.
- **Nhập JSON hoặc ZIP** nhận một tệp bài hát, tài liệu JSON chứa danh sách bài hoặc ZIP theo định dạng đã xuất. Khi một mục lỗi, các mục hợp lệ đã ghi vẫn còn. Sửa tệp và nhập lại để tiếp tục.
- **Xóa lời lưu của mục đã chọn** xóa các mục tại thiết bị. Spotify vẫn giữ lượt thích của bạn.

## Định dạng phiên bản 1

Manifest có `format: "spotify-syna-lyrics"`, `version: 1` và mảng `tracks`. Mỗi phần tử chỉ ra tệp có tên `tracks/<trackId>.json` và chứa thông tin của bài như trạng thái, tên, nghệ sĩ, nguồn và ngôn ngữ. JSON đa bài dùng cùng phần đầu nhưng mỗi phần tử là nội dung đầy đủ của một tệp bài. Tệp đơn có cấu trúc sau:

```json
{
  "trackId": "0000000000000000000001",
  "uri": "spotify:track:0000000000000000000001",
  "title": "Bài hát mô phỏng",
  "artists": ["Nghệ sĩ mô phỏng"],
  "source": "Kho lời có quyền sử dụng",
  "language": "en",
  "status": "original",
  "lines": [
    {
      "id": "0",
      "index": 0,
      "text": "A new day begins.",
      "startMs": 1250,
      "endMs": 3100,
      "translation": "Một ngày mới bắt đầu."
    }
  ]
}
```

Dòng không đồng bộ có `startMs` và `endMs` bằng `null`. Bài thiếu lời có `status: "missing"`, `source: ""` và `lines: []`. Dữ liệu được lưu tại Application Support, với tệp riêng cho từng bài. Trình kiểm tra trên macOS nằm ở `harness/lyrics-library/check.sh`.
