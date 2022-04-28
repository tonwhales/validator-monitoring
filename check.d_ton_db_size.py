import socket
import sys
sys.path.append("/usr/src/validator-monitoring")
from common import EnvEnrichedConsumer

# the following try/except block will make the custom check compatible with any Agent version
try:
    # first, try to import the base class from new versions of the Agent...
    from datadog_checks.base import AgentCheck
except ImportError:
    # ...if the above failed, the check is running in Agent version < 6.6.0
    from checks import AgentCheck

# content of the special variable __version__ will be shown in the Agent status page
__version__ = "1.0.0"
UNIX_SOCKET_PATH = "/var/tmp/ton_db_size.sock"

class DbSizeCheck(AgentCheck, EnvEnrichedConsumer):
    def check(self, instance):
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.connect(UNIX_SOCKET_PATH)
        db_size_str = s.recv(1024).decode('utf8')
        self.gauge('ton.db.size', int(db_size_str), tags=self.get_plain_tags())
