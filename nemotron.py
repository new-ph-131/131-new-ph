import requests
import json
import sys
import os

URL = "https://integrate.api.nvidia.com/v1/chat/completions"
API_KEY = "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"

headers = {
    "Authorization": f"Bearer {API_KEY}",
    "Content-Type": "application/json"
}

def ask_nemotron(prompt, file_path=None):
    file_context = ""
    if file_path:
        if os.path.exists(file_path):
            with open(file_path, "r", encoding="utf-8") as f:
                file_content = f.read()
            file_context = f"\n\n[FILE: {file_path}]\n```dart\n{file_content}\n```\n"
            print(f"📂 File read ho gayi: {file_path}")
        else:
            print(f"❌ File nahi mili: {file_path}")
            return

    full_prompt = f"{prompt}{file_context}"

    payload = {
        "model": "nvidia/nemotron-3-ultra-550b-a55b",
        "messages": [
            {
                "role": "system",
                "content": "You are an expert Flutter and Dart developer. Analyze the provided project files and instructions. Provide clear, optimized solutions and code updates."
            },
            {
                "role": "user",
                "content": full_prompt
            }
        ],
        "max_tokens": 1500,
        "temperature": 0.3
    }
    
    print("\n⏳ Nemotron 3 Ultra file analyze kar raha hai...")
    try:
        response = requests.post(URL, headers=headers, json=payload, timeout=60)
        if response.status_code == 200:
            data = response.json()
            print("\n" + "="*45)
            print("🤖 NEMOTRON 3 ULTRA SUGGESTION / CODE:")
            print("="*45 + "\n")
            print(data["choices"][0]["message"]["content"])
            print("\n" + "="*45)
        else:
            print(f"\n❌ Error ({response.status_code}): {response.text}")
    except Exception as e:
        print(f"\n❌ Error: {e}")

if __name__ == "__main__":
    if len(sys.argv) > 2 and sys.argv[1] == "-f":
        file_name = sys.argv[2]
        query = " ".join(sys.argv[3:]) if len(sys.argv) > 3 else "Is file ka code check karo aur optimize karo."
        ask_nemotron(query, file_name)
    elif len(sys.argv) > 1:
        query = " ".join(sys.argv[1:])
        ask_nemotron(query)
    else:
        query = input("\n💬 Nemotron se kya puchna chahte hain? : ")
        ask_nemotron(query)
