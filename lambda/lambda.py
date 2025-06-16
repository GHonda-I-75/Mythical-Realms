import json
import random

def lambda_handler(event, context):
    # Simulated wait-time prediction logic (replace with real ML logic if needed)
    ride_id = event.get("ride_id", "unknown")
    wait_time = random.randint(10, 120)  # Simulate wait time between 10 to 120 mins

    return {
        "statusCode": 200,
        "body": json.dumps({
            "ride_id": ride_id,
            "predicted_wait_time": wait_time
        })
    }
