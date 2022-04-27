import json

ROOT_HASH_TO_ENV = {
    "F6OpKZKqvqeFp6CQmFomXNMfMj2EnaUSOXN+Mh+wVWk=": "mainnet",
    "WPsS1IiRjT0MSD6Xvys4QYQh7rrc9x0ybzXojwJ4gH0=": "testnet",
}

class EnvEnrichedConsumer():
    def get_environment(self):
        with open("/usr/src/validator-monitoring/local.config.json") as f:
            config = json.load(f)
            root_hash = config["validator"]["zero_state"]["root_hash"]
            return ROOT_HASH_TO_ENV.get(root_hash, "env_not_known")

    def send_gauge_with_env_tag(self, name: str, value):
        self.gauge(
            name,
            value,
            tags=['SERVICE:ton', 'ENVIRONMENT:{}'.format(self.get_environment())] + self.instance.get('tags', [])
        )