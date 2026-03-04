//
//  WiFiUploadServer.swift
//  Scarlet
//
//  Local HTTP server that serves a beautiful upload page for receiving
//  IPA files from any device on the same WiFi network.
//

import Foundation
import Network
import SwiftUI

/// Local HTTP server for receiving IPA/file uploads over WiFi.
final class WiFiUploadServer: ObservableObject {

    static let shared = WiFiUploadServer()

    @Published var isRunning = false
    @Published var port: UInt16 = 0
    @Published var localIP: String = ""
    @Published var lastUploadName: String = ""

    private var listener: NWListener?

    // MARK: - Start / Stop

    func start() {
        guard listener == nil else { return }
        do {
            let params = NWParameters.tcp
            let l = try NWListener(using: params)

            l.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    switch state {
                    case .ready:
                        self?.port = l.port?.rawValue ?? 0
                        self?.localIP = Self.getWiFiAddress() ?? "127.0.0.1"
                        self?.isRunning = true
                    case .failed, .cancelled:
                        self?.isRunning = false
                    default: break
                    }
                }
            }

            l.newConnectionHandler = { [weak self] conn in
                self?.handleConnection(conn)
            }

            l.start(queue: .global(qos: .userInitiated))
            listener = l
        } catch {
            isRunning = false
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        port = 0
    }

    var serverURL: String {
        "http://\(localIP):\(port)"
    }

    // MARK: - Connection Handler

    private func handleConnection(_ conn: NWConnection) {
        conn.start(queue: .global(qos: .userInitiated))

        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            guard let self, error == nil, let data else {
                conn.cancel()
                return
            }

            let headerPeek = String(data: data.prefix(16), encoding: .utf8) ?? ""

            if headerPeek.hasPrefix("OPTIONS") {
                let resp = self.corsPreflightResponse()
                conn.send(content: resp, completion: .contentProcessed { _ in conn.cancel() })
                return
            }

            if headerPeek.hasPrefix("POST") {
                let headerStr = String(data: data.prefix(min(data.count, 8192)), encoding: .utf8) ?? ""
                var contentLength = 0
                for line in headerStr.components(separatedBy: "\r\n") {
                    if line.lowercased().hasPrefix("content-length:") {
                        contentLength = Int(line.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces) ?? "0") ?? 0
                        break
                    }
                }

                guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else {
                    conn.cancel()
                    return
                }

                let headerData = Data(data[data.startIndex..<headerEnd.upperBound])
                let initialBody = Data(data[headerEnd.upperBound...])
                let remaining = contentLength - initialBody.count

                // Stream to a temp file instead of accumulating in RAM
                let tmpRaw = FileManager.default.temporaryDirectory.appendingPathComponent("upload_\(UUID().uuidString).raw")
                FileManager.default.createFile(atPath: tmpRaw.path, contents: nil)

                guard let fh = try? FileHandle(forWritingTo: tmpRaw) else {
                    conn.cancel()
                    return
                }

                // Write initial body chunk
                fh.write(initialBody)

                if remaining <= 0 {
                    fh.closeFile()
                    self.processUploadFile(headerData: headerData, rawFile: tmpRaw, connection: conn)
                } else {
                    self.streamToFile(connection: conn,
                                     headerData: headerData,
                                     fileHandle: fh,
                                     rawFile: tmpRaw,
                                     remaining: remaining)
                }
            } else {
                let html = Self.uploadPageHTML
                let response = self.httpResponse(status: "200 OK", contentType: "text/html; charset=utf-8", body: Data(html.utf8))
                conn.send(content: response, completion: .contentProcessed { _ in conn.cancel() })
            }
        }
    }

    /// Streams upload body chunks directly to disk — no RAM accumulation.
    private func streamToFile(connection: NWConnection,
                               headerData: Data,
                               fileHandle: FileHandle,
                               rawFile: URL,
                               remaining: Int) {
        let chunkSize = min(remaining, 512 * 1024) // 512 KB chunks
        connection.receive(minimumIncompleteLength: 1, maximumLength: chunkSize) { [weak self] data, _, _, error in
            guard let self else {
                fileHandle.closeFile()
                try? FileManager.default.removeItem(at: rawFile)
                connection.cancel()
                return
            }

            guard error == nil, let data else {
                fileHandle.closeFile()
                try? FileManager.default.removeItem(at: rawFile)
                connection.cancel()
                return
            }

            fileHandle.write(data)
            let newRemaining = remaining - data.count

            if newRemaining <= 0 {
                fileHandle.closeFile()
                self.processUploadFile(headerData: headerData, rawFile: rawFile, connection: connection)
            } else {
                self.streamToFile(connection: connection,
                                  headerData: headerData,
                                  fileHandle: fileHandle,
                                  rawFile: rawFile,
                                  remaining: newRemaining)
            }
        }
    }

    // MARK: - Process Uploaded File

    private func processUploadFile(headerData: Data, rawFile: URL, connection: NWConnection) {
        defer { try? FileManager.default.removeItem(at: rawFile) }

        guard let rawData = try? Data(contentsOf: rawFile, options: .mappedIfSafe) else {
            let resp = httpResponse(status: "500 Internal Server Error", contentType: "text/html; charset=utf-8",
                                    body: Data(Self.responseHTML(success: false, message: "Failed to read upload").utf8))
            connection.send(content: resp, completion: .contentProcessed { _ in connection.cancel() })
            return
        }

        guard let headerStr = String(data: headerData, encoding: .utf8),
              let boundaryLine = headerStr.components(separatedBy: "\r\n").first(where: { $0.lowercased().contains("boundary=") }),
              let boundary = boundaryLine.components(separatedBy: "boundary=").last?.trimmingCharacters(in: .whitespaces) else {
            let resp = httpResponse(status: "400 Bad Request", contentType: "text/html; charset=utf-8",
                                    body: Data(Self.responseHTML(success: false, message: "Invalid upload").utf8))
            connection.send(content: resp, completion: .contentProcessed { _ in connection.cancel() })
            return
        }

        guard let dispositionRange = rawData.range(of: Data("Content-Disposition:".utf8)),
              let dispLineEnd = rawData[dispositionRange.lowerBound...].range(of: Data("\r\n".utf8)),
              let dispLine = String(data: rawData[dispositionRange.lowerBound..<dispLineEnd.lowerBound], encoding: .utf8) else {
            let resp = httpResponse(status: "400 Bad Request", contentType: "text/html; charset=utf-8",
                                    body: Data(Self.responseHTML(success: false, message: "Could not parse upload").utf8))
            connection.send(content: resp, completion: .contentProcessed { _ in connection.cancel() })
            return
        }

        var fileName = "upload.ipa"
        if let fnRange = dispLine.range(of: "filename=\""),
           let fnEnd = dispLine[fnRange.upperBound...].range(of: "\"") {
            fileName = String(dispLine[fnRange.upperBound..<fnEnd.lowerBound])
        }

        guard let fileStart = rawData[dispositionRange.lowerBound...].range(of: Data("\r\n\r\n".utf8)) else {
            let resp = httpResponse(status: "400 Bad Request", contentType: "text/html; charset=utf-8",
                                    body: Data(Self.responseHTML(success: false, message: "No file data").utf8))
            connection.send(content: resp, completion: .contentProcessed { _ in connection.cancel() })
            return
        }

        var fileData = rawData[fileStart.upperBound...]

        let closingBoundary = Data("\r\n--\(boundary)".utf8)
        if let endRange = fileData.range(of: closingBoundary) {
            fileData = fileData[fileData.startIndex..<endRange.lowerBound]
        }

        let destFile = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try Data(fileData).write(to: destFile)

            DispatchQueue.main.async {
                self.lastUploadName = fileName
                ImportedAppsManager.shared.importIPA(from: destFile)
            }

            let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(fileData.count), countStyle: .file)
            let okHTML = Self.responseHTML(success: true, message: "\(fileName) (\(sizeStr)) uploaded!")
            let resp = httpResponse(status: "200 OK", contentType: "text/html; charset=utf-8", body: Data(okHTML.utf8))
            connection.send(content: resp, completion: .contentProcessed { _ in connection.cancel() })
        } catch {
            let resp = httpResponse(status: "500 Internal Server Error", contentType: "text/html; charset=utf-8",
                                    body: Data(Self.responseHTML(success: false, message: "Save failed: \(error.localizedDescription)").utf8))
            connection.send(content: resp, completion: .contentProcessed { _ in connection.cancel() })
        }
    }

    // MARK: - HTTP Response Builders

    private func httpResponse(status: String, contentType: String, body: Data) -> Data {
        let header = [
            "HTTP/1.1 \(status)",
            "Content-Type: \(contentType)",
            "Content-Length: \(body.count)",
            "Access-Control-Allow-Origin: *",
            "Access-Control-Allow-Methods: GET, POST, OPTIONS",
            "Access-Control-Allow-Headers: Content-Type",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")
        return Data(header.utf8) + body
    }

    private func corsPreflightResponse() -> Data {
        let header = [
            "HTTP/1.1 204 No Content",
            "Access-Control-Allow-Origin: *",
            "Access-Control-Allow-Methods: GET, POST, OPTIONS",
            "Access-Control-Allow-Headers: Content-Type, Content-Length",
            "Access-Control-Max-Age: 86400",
            "Content-Length: 0",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")
        return Data(header.utf8)
    }

    // MARK: - WiFi IP

    static func getWiFiAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let iface = ptr.pointee
            let family = iface.ifa_addr.pointee.sa_family
            guard family == UInt8(AF_INET) else { continue }

            let name = String(cString: iface.ifa_name)
            guard name == "en0" else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(iface.ifa_addr, socklen_t(iface.ifa_addr.pointee.sa_len),
                        &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
            address = String(cString: hostname)
        }
        return address
    }

    // MARK: - Upload Page HTML

    static let uploadPageHTML: String = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Scarlet · WiFi Upload</title>
    <style>
    *{margin:0;padding:0;box-sizing:border-box}
    body{
      background:#0a0a0c;color:#fff;font-family:-apple-system,BlinkMacSystemFont,'SF Pro','Inter',sans-serif;
      min-height:100vh;display:flex;align-items:center;justify-content:center;
    }
    .container{
      width:100%;max-width:480px;padding:32px 24px;
    }
    .header{text-align:center;margin-bottom:40px}
    .logo{
      width:64px;height:64px;border-radius:16px;margin:0 auto 16px;
      background:linear-gradient(135deg,#e63946,#b71c2c);
      display:flex;align-items:center;justify-content:center;
      box-shadow:0 8px 32px rgba(230,57,70,0.3);
    }
    .logo svg{width:32px;height:32px;fill:#fff}
    h1{font-size:24px;font-weight:700;letter-spacing:-0.5px}
    .subtitle{font-size:13px;color:rgba(255,255,255,0.3);margin-top:6px;font-weight:500}

    .drop-zone{
      border:2px dashed rgba(255,255,255,0.08);border-radius:20px;
      padding:48px 24px;text-align:center;cursor:pointer;
      transition:all 0.3s ease;position:relative;
      background:rgba(255,255,255,0.02);
    }
    .drop-zone:hover,.drop-zone.drag-over{
      border-color:rgba(230,57,70,0.5);
      background:rgba(230,57,70,0.04);
    }
    .drop-zone .icon{
      width:48px;height:48px;border-radius:14px;margin:0 auto 16px;
      background:rgba(230,57,70,0.1);display:flex;align-items:center;justify-content:center;
    }
    .drop-zone .icon svg{width:24px;height:24px;fill:#e63946}
    .drop-zone p{font-size:14px;color:rgba(255,255,255,0.4);line-height:1.6}
    .drop-zone .browse{color:#e63946;font-weight:600;text-decoration:underline}
    .drop-zone input{display:none}

    .progress-wrap{
      margin-top:24px;display:none;
    }
    .progress-wrap.active{display:block}
    .file-info{
      display:flex;align-items:center;gap:12px;
      padding:14px 16px;border-radius:14px;
      background:rgba(255,255,255,0.03);border:1px solid rgba(255,255,255,0.06);
      margin-bottom:16px;
    }
    .file-info .fi-icon{
      width:40px;height:40px;border-radius:10px;flex-shrink:0;
      background:linear-gradient(135deg,#e63946,#b71c2c);
      display:flex;align-items:center;justify-content:center;
    }
    .file-info .fi-icon svg{width:20px;height:20px;fill:#fff}
    .file-info .fi-text{flex:1;overflow:hidden}
    .file-info .fi-name{font-size:13px;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
    .file-info .fi-size{font-size:11px;color:rgba(255,255,255,0.3);margin-top:2px}
    .bar-bg{
      height:4px;border-radius:2px;background:rgba(255,255,255,0.06);overflow:hidden;
    }
    .bar-fill{
      height:100%;border-radius:2px;width:0%;
      background:linear-gradient(90deg,#e63946,#ff6b6b);
      transition:width 0.3s ease;
    }
    .status{
      text-align:center;font-size:12px;color:rgba(255,255,255,0.3);
      margin-top:10px;font-weight:500;
    }

    .footer{
      text-align:center;margin-top:40px;font-size:11px;
      color:rgba(255,255,255,0.1);font-weight:500;
    }
    </style>
    </head>
    <body>
    <div class="container">
      <div class="header">
        <div class="logo">
          <svg viewBox="0 0 24 24"><path d="M19 9h-4V3H9v6H5l7 7 7-7zM5 18v2h14v-2H5z"/></svg>
        </div>
        <h1>Scarlet</h1>
        <p class="subtitle">WiFi Upload</p>
      </div>

      <div class="drop-zone" id="dropZone">
        <div class="icon">
          <svg viewBox="0 0 24 24"><path d="M19 9h-4V3H9v6H5l7 7 7-7zM5 18v2h14v-2H5z"/></svg>
        </div>
        <p>Drop <strong>.ipa</strong> files here<br>or <span class="browse">tap to browse</span></p>
        <input type="file" id="fileInput" accept=".ipa,.p12,.mobileprovision">
      </div>

      <div class="progress-wrap" id="progressWrap">
        <div class="file-info">
          <div class="fi-icon">
            <svg viewBox="0 0 24 24"><path d="M14 2H6c-1.1 0-2 .9-2 2v16c0 1.1.9 2 2 2h12c1.1 0 2-.9 2-2V8l-6-6zm-1 7V3.5L18.5 9H13z"/></svg>
          </div>
          <div class="fi-text">
            <div class="fi-name" id="fileName">—</div>
            <div class="fi-size" id="fileSize">—</div>
          </div>
        </div>
        <div class="bar-bg"><div class="bar-fill" id="barFill"></div></div>
        <div class="status" id="status">Uploading...</div>
      </div>

      <div class="footer">Scarlet v2.0 · DebianArch64</div>
    </div>

    <script>
    const dropZone=document.getElementById('dropZone');
    const fileInput=document.getElementById('fileInput');
    const progressWrap=document.getElementById('progressWrap');
    const barFill=document.getElementById('barFill');
    const statusEl=document.getElementById('status');

    dropZone.addEventListener('click',()=>fileInput.click());
    dropZone.addEventListener('dragover',e=>{e.preventDefault();dropZone.classList.add('drag-over')});
    dropZone.addEventListener('dragleave',()=>dropZone.classList.remove('drag-over'));
    dropZone.addEventListener('drop',e=>{e.preventDefault();dropZone.classList.remove('drag-over');if(e.dataTransfer.files.length)uploadFile(e.dataTransfer.files[0])});
    fileInput.addEventListener('change',()=>{if(fileInput.files.length)uploadFile(fileInput.files[0])});

    function showErr(msg){statusEl.textContent=msg;statusEl.style.color='#ff6b6b'}

    function uploadFile(file){
      document.getElementById('fileName').textContent=file.name;
      document.getElementById('fileSize').textContent=formatSize(file.size);
      progressWrap.classList.add('active');
      dropZone.style.display='none';
      barFill.style.width='0%';
      statusEl.textContent='Uploading...';
      statusEl.style.color='';

      try{
        const xhr=new XMLHttpRequest();
        xhr.timeout=0;
        const fd=new FormData();
        fd.append('file',file);

        xhr.upload.onprogress=e=>{
          if(e.lengthComputable){
            const pct=Math.round(e.loaded/e.total*100);
            barFill.style.width=pct+'%';
            statusEl.textContent='Uploading... '+pct+'%';
          }
        };
        xhr.onload=()=>{
          if(xhr.status>=200&&xhr.status<300){
            barFill.style.width='100%';
            statusEl.textContent='\\u2713 Upload complete!';
            statusEl.style.color='#e63946';
            setTimeout(()=>{
              progressWrap.classList.remove('active');
              dropZone.style.display='';
              statusEl.style.color='';
              fileInput.value='';
            },2500);
          }else{
            showErr('Server error: '+xhr.status+' '+xhr.statusText);
          }
        };
        xhr.onerror=()=>{
          showErr('Network error (readyState='+xhr.readyState+', status='+xhr.status+')');
        };
        xhr.onabort=()=>{showErr('Upload aborted')};
        xhr.ontimeout=()=>{showErr('Upload timed out')};
        xhr.onreadystatechange=()=>{
          if(xhr.readyState===4&&xhr.status===0){
            showErr('Connection refused/reset (state=4,status=0)');
          }
        };
        xhr.open('POST',window.location.origin+'/');
        xhr.send(fd);
      }catch(e){
        showErr('JS Error: '+e.message);
      }
    }

    function formatSize(b){
      if(b<1024)return b+' B';
      if(b<1048576)return (b/1024).toFixed(1)+' KB';
      if(b<1073741824)return (b/1048576).toFixed(1)+' MB';
      return (b/1073741824).toFixed(2)+' GB';
    }
    </script>
    </body>
    </html>
    """

    // MARK: - Response HTML

    static func responseHTML(success: Bool, message: String) -> String {
        let color = success ? "#e63946" : "#ff4444"
        let icon = success
            ? "<svg viewBox='0 0 24 24' width='32' height='32' fill='\(color)'><path d='M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z'/></svg>"
            : "<svg viewBox='0 0 24 24' width='32' height='32' fill='\(color)'><path d='M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-2h2v2zm0-4h-2V7h2v6z'/></svg>"

        return """
        <!DOCTYPE html><html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>Scarlet Upload</title>
        <style>*{margin:0;padding:0;box-sizing:border-box}body{background:#0a0a0c;color:#fff;font-family:-apple-system,sans-serif;min-height:100vh;display:flex;align-items:center;justify-content:center;text-align:center}.c{padding:32px}\(success ? "" : " .msg{color:#ff6b6b}")</style>
        </head><body><div class="c">\(icon)<p class="msg" style="margin-top:16px;font-size:15px;font-weight:600">\(message)</p>
        <p style="margin-top:12px"><a href="/" style="color:\(color);font-size:13px">← Upload another</a></p></div></body></html>
        """
    }
}
