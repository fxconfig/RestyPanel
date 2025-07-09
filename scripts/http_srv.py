#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
简单的HTTP Ping服务
提供基本的ping和健康检查功能
"""

import json
import time
import socket
import urllib.request
import urllib.error
import argparse
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs


class PingHandler(BaseHTTPRequestHandler):
    """HTTP请求处理器"""
    
    def do_GET(self):
        """处理GET请求"""
        parsed_path = urlparse(self.path)
        path = parsed_path.path
        query_params = parse_qs(parsed_path.query)
        
        if path == '/ping':
            self.handle_ping()
        elif path == '/health':
            self.handle_health()
        elif path == '/ping-url':
            target_url = query_params.get('url', [None])[0]
            self.handle_ping_url(target_url)
        else:
            self.handle_not_found()
    
    def handle_ping(self):
        """处理基本ping请求"""
        # 打印ping请求信息
        client_ip = self.client_address[0]
        client_port = self.client_address[1]
        user_agent = self.headers.get('User-Agent', 'Unknown')
        host_header = self.headers.get('Host', 'Unknown')
        forwarded_for = self.headers.get('X-Forwarded-For', None)
        real_ip = self.headers.get('X-Real-IP', None)
        
        # 确定真实客户端IP
        real_client_ip = real_ip or forwarded_for or client_ip
        
        print(f"🏓 [PING请求] {time.strftime('%Y-%m-%d %H:%M:%S')} - "
              f"客户端: {real_client_ip}:{client_port}")
        print(f"   └─ Host: {host_header} | User-Agent: {user_agent[:50]}{'...' if len(user_agent) > 50 else ''}")
        
        # 获取服务器端口
        server_port = self.server.server_address[1]
        
        response = {
            "status": "ok",
            "message": "pong",
            "timestamp": time.time(),
            "server": f"python-http-ping:{server_port}",
            "server_info": {
                "port": server_port,
                "host": self.server.server_address[0]
            },
            "request_info": {
                "client_ip": real_client_ip,
                "original_client": f"{client_ip}:{client_port}",
                "user_agent": user_agent,
                "host_header": host_header
            }
        }
        self.send_json_response(200, response)
    
    def handle_health(self):
        """处理健康检查请求"""
        # 打印健康检查请求信息
        client_ip = self.client_address[0]
        client_port = self.client_address[1]
        user_agent = self.headers.get('User-Agent', 'Unknown')
        host_header = self.headers.get('Host', 'Unknown')
        forwarded_for = self.headers.get('X-Forwarded-For', None)
        real_ip = self.headers.get('X-Real-IP', None)
        
        # 确定真实客户端IP
        real_client_ip = real_ip or forwarded_for or client_ip
        
        print(f"🏥 [健康检查] {time.strftime('%Y-%m-%d %H:%M:%S')} - "
              f"客户端: {real_client_ip}:{client_port}")
        print(f"   └─ Host: {host_header} | User-Agent: {user_agent[:50]}{'...' if len(user_agent) > 50 else ''}")
        
        if forwarded_for:
            print(f"   └─ X-Forwarded-For: {forwarded_for}")
        if real_ip:
            print(f"   └─ X-Real-IP: {real_ip}")
        
        # 获取服务器端口（从程序启动参数或配置中获取）
        server_port = self.server.server_address[1]
        
        response = {
            "status": "healthy",
            "timestamp": time.time(),
            "uptime": time.time(),
            "version": "1.0.0",
            "server_info": {
                "port": server_port,
                "host": self.server.server_address[0]
            },
            "request_info": {
                "client_ip": real_client_ip,
                "original_client": f"{client_ip}:{client_port}",
                "user_agent": user_agent,
                "host_header": host_header
            }
        }
        self.send_json_response(200, response)
    
    def handle_ping_url(self, target_url):
        """ping指定的URL"""
        if not target_url:
            response = {
                "error": "需要提供url参数",
                "example": "/ping-url?url=http://example.com"
            }
            self.send_json_response(400, response)
            return
        
        try:
            start_time = time.time()
            with urllib.request.urlopen(target_url, timeout=10) as response:
                end_time = time.time()
                response_time = round((end_time - start_time) * 1000, 2)  # 毫秒
                
                ping_result = {
                    "url": target_url,
                    "status": "success",
                    "status_code": response.getcode(),
                    "response_time_ms": response_time,
                    "timestamp": time.time()
                }
                self.send_json_response(200, ping_result)
                
        except urllib.error.HTTPError as e:
            response = {
                "url": target_url,
                "status": "http_error",
                "error_code": e.code,
                "error_message": str(e),
                "timestamp": time.time()
            }
            self.send_json_response(200, response)
            
        except urllib.error.URLError as e:
            response = {
                "url": target_url,
                "status": "url_error",
                "error_message": str(e),
                "timestamp": time.time()
            }
            self.send_json_response(200, response)
            
        except Exception as e:
            response = {
                "url": target_url,
                "status": "error",
                "error_message": str(e),
                "timestamp": time.time()
            }
            self.send_json_response(500, response)
    
    def handle_not_found(self):
        """处理404请求"""
        response = {
            "error": "Not Found",
            "available_endpoints": [
                "/ping - 基本ping检查",
                "/health - 健康状态检查", 
                "/ping-url?url=<target_url> - ping指定URL"
            ]
        }
        self.send_json_response(404, response)
    
    def send_json_response(self, status_code, data):
        """发送JSON响应"""
        self.send_response(status_code)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        
        json_data = json.dumps(data, ensure_ascii=False, indent=2)
        self.wfile.write(json_data.encode('utf-8'))
    
    def log_message(self, format, *args):
        """自定义日志格式"""
        print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {format % args}")


def main():
    """主函数"""
    # 解析命令行参数
    parser = argparse.ArgumentParser(
        description='HTTP Ping 服务 - 提供基本的ping和健康检查功能',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
使用示例:
  python http_ping.py                    # 使用默认端口 8080
  python http_ping.py -p 8000           # 指定端口 8000
  python http_ping.py --port 9000       # 指定端口 9000
  python http_ping.py --host 127.0.0.1  # 指定监听地址和端口

可用端点:
  /ping                                  # 基本ping检查
  /health                               # 健康状态检查
  /ping-url?url=<target_url>            # ping指定URL
        """
    )
    
    parser.add_argument(
        '-p', '--port',
        type=int,
        default=8080,
        help='服务监听端口 (默认: 8080)'
    )
    
    parser.add_argument(
        '--host',
        type=str,
        default='0.0.0.0',
        help='服务监听地址 (默认: 0.0.0.0, 监听所有接口)'
    )
    
    args = parser.parse_args()
    
    # 配置
    HOST = args.host
    PORT = args.port
    
    # 检查端口是否可用
    try:
        test_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        test_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        test_socket.bind((HOST, PORT))
        test_socket.close()
    except OSError as e:
        print(f"错误: 端口 {PORT} 不可用: {e}")
        print(f"请尝试使用其他端口，例如: python {__file__} -p {PORT + 1}")
        return 1
    
    # 创建服务器
    server = HTTPServer((HOST, PORT), PingHandler)
    
    print(f"启动HTTP Ping服务...")
    print(f"服务地址: http://{HOST}:{PORT}")
    print(f"监听地址: {HOST}")
    print(f"监听端口: {PORT}")
    print(f"")
    print(f"可用端点:")
    print(f"  - http://localhost:{PORT}/ping")
    print(f"  - http://localhost:{PORT}/health") 
    print(f"  - http://localhost:{PORT}/ping-url?url=<target_url>")
    print(f"")
    print(f"按 Ctrl+C 停止服务")
    
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n正在停止服务...")
        server.server_close()
        print("服务已停止")
        return 0
    except Exception as e:
        print(f"服务器错误: {e}")
        return 1


if __name__ == '__main__':
    exit(main()) 