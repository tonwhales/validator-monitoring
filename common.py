import json

ROOT_HASH_TO_ENV = {
    "F6OpKZKqvqeFp6CQmFomXNMfMj2EnaUSOXN+Mh+wVWk=": "mainnet",
    "WPsS1IiRjT0MSD6Xvys4QYQh7rrc9x0ybzXojwJ4gH0=": "testnet",
}
LOCAL_CONFIG_PATH = "/usr/src/validator-monitoring/local.config.json"

class EnvEnrichedConsumer():
    def get_environment(self):
        with open(LOCAL_CONFIG_PATH) as f:
            config = json.load(f)
            root_hash = config["validator"]["zero_state"]["root_hash"]
            return ROOT_HASH_TO_ENV.get(root_hash, "env_not_known")

    
    def get_plain_tags(self):
        return ['SERVICE:ton'] + self.instance.get('tags', [])

    def get_tags(self):
        tags = ['SERVICE:ton', 'ENVIRONMENT:{}'.format(self.get_environment())]
        return tags + self.instance.get('tags', [])


    def send_gauge_with_env_tag(self, name: str, value):
        self.gauge(name, value, tags=self.get_tags())
    

    def send_count_with_env_tag(self, name: str, value):
        self.count(name, value, tags=self.get_tags())