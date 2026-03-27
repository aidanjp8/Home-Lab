from flask import Flask, jsonify
from flask_cors import CORS
import os

app = Flask(__name__)
CORS(app)

@app.route('/stats')
def get_stats():
    # Get CPU Temp (Standard Linux)
    try:
        temp_raw = os.popen("sensors | grep 'Package id 0' | awk '{print $4}'").read().strip()
        temp = temp_raw if temp_raw else "N/A"
    except:
        temp = "Error"

    # Security: Count failed SSH logins in the last 24 hours
    failed_logins = os.popen("grep 'Failed password' /var/log/auth.log | wc -l").read().strip()

    return jsonify({
        "temp": temp,
        "security_breaks": int(failed_logins),
        "status": "online"
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
