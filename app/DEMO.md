# Demo: Flask hello

**Framework:** Flask (Python). **Moving parts locally:** none. No database, queue or async.

The app is a stand-in workload. Its only job is to be deployed into the landing zone's app spoke so you can prove traffic flows Front Door → app → firewall.

## Run it

```bash
cd app
python3 -m venv .venv && . .venv/bin/activate
pip install -r requirements.txt
```

```bash
pytest                    # 2 tests
python app.py             # serves on http://localhost:8000
```

## Try it

```bash
curl localhost:8000/          # {"env":"dev","service":"landing-zone-demo"}
curl localhost:8000/health    # {"status":"ok"}
APP_ENV=prod python app.py    # same app, env changes in the response
```

## Docker

```bash
docker build -t landing-zone-demo . && docker run -p 8000:8000 landing-zone-demo
```

## What to learn

`@app.get` maps a URL to a function that returns JSON. That is all of Flask you need here.
