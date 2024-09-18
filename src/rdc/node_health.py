from flask import Flask, Response
import subprocess

app = Flask(__name__)

@app.route('/node_health')
def metrics():
    result = subprocess.run(['/usr/local/bin/node_health.sh'], capture_output=True, text=True)
    return Response(result.stdout, mimetype='text/plain')

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5051)