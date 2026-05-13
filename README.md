# Nistula Technical Assessment

This project contains:
- Part 1: FastAPI webhook service with query classification, AI response generation, and confidence-based routing.
- Part 2: PostgreSQL schema in `schema.sql`.
- Part 3: Written explanations in `thinking.md`.

## Project Structure
```
nistula-technical-assessment/
|-- src/
|   |-- main.py
|   |-- models.py
|   |-- classifier.py
|   |-- property_context.py
|   |-- ai_handler.py
|   |-- confidence.py
|   `-- test_requests.py
|-- schema.sql
|-- thinking.md
|-- README.md
|-- requirements.txt
|-- .env.example
`-- .gitignore
```

## Setup
1. Create and activate a virtual environment.
2. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```
3. Copy `.env.example` to `.env` and set your `ANTHROPIC_API_KEY`.

## Run API
```bash
uvicorn src.main:app --reload
```

## Run Test Requests
After server starts:
```bash
python src/test_requests.py
```