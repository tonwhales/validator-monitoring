import subprocess
import re
import datetime
# the following try/except block will make the custom check compatible with any Agent version
try:
    # first, try to import the base class from new versions of the Agent...
    from datadog_checks.base import AgentCheck
except ImportError:
    # ...if the above failed, the check is running in Agent version < 6.6.0
    from checks import AgentCheck

# content of the special variable __version__ will be shown in the Agent status page
__version__ = "1.0.0"
TRIVIAL_HEALTH_IDENTIFICATIOPN_STRING = 'latest masterchain block known to server is'
UNIX_TIME_RE = re.compile('(?:' + TRIVIAL_HEALTH_IDENTIFICATIOPN_STRING + ' .*created at )(\d{10})')

class HelloCheck(AgentCheck):
    def send_gauge(self, value: int):
         self.gauge('lite.client.last.block.age.seconds', int(value), tags=['SERVICE:lite-clien'] + self.instance.get('tags', []))


    def get_replication_lag(self):
        output = error = exit_code = None
        try:
            process = subprocess.Popen(
                    ['/usr/bin/ton/lite-client/lite-client', '-C', '/usr/bin/ton/local.config.json', '-c', 'last'],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    encoding='utf8'
            );
            # huge timeout is for case of very high CPU load
            output,error = process.communicate(timeout=2)
            exit_code = process.wait(timeout=2)
        except Exception as e:
            self.log.error("Got error during communication with lite-client binary:")
            self.log.error(e)
        if output:
            last_line = output.rstrip().splitlines()[-1]
            if TRIVIAL_HEALTH_IDENTIFICATIOPN_STRING not in last_line:
                # FIXME: Add separate datadog-level checks for any case of unpredicted output
                self.log.error("Unexpexted output from lite-client.")
            else:
                unix_time_match = UNIX_TIME_RE.match(last_line)
                if not unix_time_match:
                    self.log.error("Got output from lite-client, but format is unexpexted.")
                else:
                    matched_groups = unix_time_match.groups()
                    if not matched_groups:
                        self.log.error("Somehow the output matched regex, but we got emty groups tuple")
                    else:
                        unix_time_str = matched_groups[0]
                        # we have ONLY digits now and quantity of them is strictly 10, so no need o make extra validations

                        ts = datetime.datetime.utcfromtimestamp(int(unix_time_str))
                        now = datetime.datetime.utcnow()
                        diff = now - ts
                        return diff.total_seconds()

        else:
            self.log.error("Got zero output from lite-lient.")

        if error and exit_code != 0:
            self.log.error(error.strip())
            if output:
                self.log.error(output)
        return None


    def check(self, instance):
        for _ in range(10):
            replication_lag = self.get_replication_lag()
            if replication_lag is not None:
                self.send_gauge(replication_lag)
                break
        else:
            # If success path has not been reached, it is better to light up alert anyway
            self.send_gauge(1000)
