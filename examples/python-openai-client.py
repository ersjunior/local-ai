"""Exemplo mínimo: chamar o gateway local-ai com o SDK oficial da OpenAI.

    pip install openai
    OPENAI_BASE_URL=http://HOST:4000/v1 OPENAI_API_KEY=sk-... python python-openai-client.py
"""
import os
from openai import OpenAI

client = OpenAI(
    base_url=os.environ.get("OPENAI_BASE_URL", "http://localhost:4000/v1"),
    api_key=os.environ.get("OPENAI_API_KEY", "sk-master-change-me"),
)

resp = client.chat.completions.create(
    model="chat-cuts",  # nome lógico — o gateway roteia para o backend
    messages=[{"role": "user", "content": "Devolva {\"hello\": \"world\"} em JSON."}],
    response_format={"type": "json_object"},
)

print(resp.choices[0].message.content)
