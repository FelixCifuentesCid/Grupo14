import os
import base64
import mimetypes
from flask import Flask, request, jsonify
from flask_cors import CORS
import requests
from dotenv import load_dotenv

# Carga automática del archivo .env
load_dotenv(dotenv_path=os.path.join(os.path.dirname(__file__), ".env"))

app = Flask(__name__)
CORS(app)

API_KEY = os.getenv("DASHSCOPE_API_KEY")
REGION = (os.getenv("DASHSCOPE_REGION") or "intl").lower()
PORT = int(os.getenv("PORT", "8000"))

GEN_ENDPOINT = (
    "https://dashscope-intl.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation"
    if REGION == "intl"
    else "https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation"
)

def _headers():
    if not API_KEY:
        raise RuntimeError("Falta DASHSCOPE_API_KEY en .env")
    return {"Authorization": f"Bearer {API_KEY}", "Content-Type": "application/json"}

def _encode_file_to_data_uri(file_storage):
    data = file_storage.read()
    if not data:
        return None
    mime_type = file_storage.mimetype or mimetypes.guess_type(file_storage.filename)[0] or "application/octet-stream"
    b64 = base64.b64encode(data).decode("utf-8")
    return f"data:{mime_type};base64,{b64}"

def _extract_image_urls_from_response(data):
    urls = []
    out = (data or {}).get("output") or {}
    if "results" in out:
        for res in out.get("results", []):
            url = res.get("url") or res.get("image")
            if url:
                urls.append(url)
    if "choices" in out:
        for ch in out.get("choices", []):
            msg = ch.get("message") or {}
            for c in (msg.get("content") or []):
                if "image" in c:
                    urls.append(c["image"])
    return urls

@app.get("/health")
def health():
    return jsonify({"ok": bool(API_KEY), "region": REGION})

@app.post("/generate")
def generate():
    payload = request.get_json(force=True, silent=True) or {}
    prompt = payload.get("prompt")
    if not prompt:
        return jsonify({"error": "Falta 'prompt'"}), 400

    body = {
        "model": payload.get("model", "qwen-image-plus"),
        "input": {"messages": [{"role": "user", "content": [{"text": prompt}]}]},
        "parameters": {
            "size": payload.get("size", "1328*1328"),
            "negative_prompt": payload.get("negative_prompt", ""),
            "watermark": bool(payload.get("watermark", False)),
            "prompt_extend": bool(payload.get("prompt_extend", True)),
        },
    }

    resp = requests.post(GEN_ENDPOINT, headers=_headers(), json=body, timeout=90)
    data = resp.json()
    if resp.status_code != 200:
        return jsonify(data), resp.status_code
    image_urls = _extract_image_urls_from_response(data)
    return jsonify({"image_urls": image_urls, "raw": data})

@app.post("/edit")
def edit():
    images, instruction = [], None

    if request.content_type and request.content_type.startswith("multipart/form-data"):
        instruction = request.form.get("instruction") or request.form.get("prompt")
        for field in ("image1", "image2", "image3"):
            f = request.files.get(field)
            if f:
                data_uri = _encode_file_to_data_uri(f)
                if data_uri:
                    images.append(data_uri)
    else:
        payload = request.get_json(force=True, silent=True) or {}
        instruction = payload.get("instruction") or payload.get("prompt")
        images = payload.get("images") or payload.get("image_urls") or []

    if not instruction:
        return jsonify({"error": "Falta 'instruction' o 'prompt'"}), 400
    if not images:
        return jsonify({"error": "Debes enviar al menos una imagen"}), 400

    content = [{"image": img} for img in images[:3]]
    content.append({"text": instruction})

    body = {
        "model": "qwen-image-edit",
        "input": {"messages": [{"role": "user", "content": content}]},
        "parameters": {"negative_prompt": " ", "watermark": False},
    }

    resp = requests.post(GEN_ENDPOINT, headers=_headers(), json=body, timeout=120)
    data = resp.json()
    if resp.status_code != 200:
        return jsonify(data), resp.status_code
    image_urls = _extract_image_urls_from_response(data)
    return jsonify({"image_urls": image_urls, "raw": data})

@app.post("/chat")
def chat():
    payload = request.get_json(force=True, silent=True) or {}
    images = payload.get("images") or payload.get("image_urls") or []
    prompt = payload.get("prompt")

    if not prompt and "messages" in payload:
        for msg in reversed(payload["messages"]):
            if msg.get("role") == "user":
                for item in msg.get("content", []):
                    if "text" in item:
                        prompt = item["text"]
                    if "image" in item:
                        images.append(item["image"])
                break

    if not prompt:
        return jsonify({"error": "Falta 'prompt'"}), 400

    if images:
        content = [{"image": img} for img in images[:3]]
        content.append({"text": prompt})
        body = {
            "model": "qwen-image-edit",
            "input": {"messages": [{"role": "user", "content": content}]},
            "parameters": {"negative_prompt": " ", "watermark": False},
        }
    else:
        body = {
            "model": payload.get("model", "qwen-image-plus"),
            "input": {"messages": [{"role": "user", "content": [{"text": prompt}]}]},
            "parameters": {
                "size": payload.get("size", "1328*1328"),
                "negative_prompt": payload.get("negative_prompt", ""),
                "watermark": bool(payload.get("watermark", False)),
                "prompt_extend": bool(payload.get("prompt_extend", True)),
            },
        }

    resp = requests.post(GEN_ENDPOINT, headers=_headers(), json=body, timeout=120)
    data = resp.json()
    if resp.status_code != 200:
        return jsonify(data), resp.status_code
    image_urls = _extract_image_urls_from_response(data)
    return jsonify({"image_urls": image_urls, "raw": data})

if __name__ == "__main__":
    print(f"🚀 Servidor Flask corriendo en http://127.0.0.1:{PORT}")
    app.run(host="0.0.0.0", port=PORT)
