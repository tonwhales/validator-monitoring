import sys
sys.path.append("/usr/src/mytonctrl")
sys.path.append("/usr/local/lib/python3.8/dist-packages/")
sys.path.append("/usr/src/validator-monitoring")
from common import EnvEnrichedConsumer
import mytonctrl
import mytoncore

# the following try/except block will make the custom check compatible with any Agent version
try:
    # first, try to import the base class from new versions of the Agent...
    from datadog_checks.base import AgentCheck
except ImportError:
    # ...if the above failed, the check is running in Agent version < 6.6.0
    from checks import AgentCheck

# content of the special variable __version__ will be shown in the Agent status page
__version__ = "1.0.0"

class ValidatorEfficiencyCheck(AgentCheck, EnvEnrichedConsumer):
    def send_gauge(self, name, value):
        self.gauge(name, value, tags=self.get_plain_tags())


    def check(self, instance):
        mytoncore.local.buffer["localdbFileName"] = "/usr/local/bin/mytoncore/mytoncore.db"
        toncore = mytonctrl.MyTonCore()
        toncore.liteClient.configPath = "/usr/src/validator-monitoring/local.config.json"
        mytoncore.local.db["liteServers"] = [0]
        if len(list(filter(lambda v: v["adnlAddr"] == toncore.GetAdnlAddr(), toncore.GetConfig34()["validators"]))) != 0:
            self.send_gauge('ton.validator.efficiency', toncore.GetValidatorEfficiency(adnlAddr=toncore.GetAdnlAddr()))
            self.send_gauge('ton.validator.index', toncore.GetValidatorIndex(adnlAddr=toncore.GetAdnlAddr()))
        else:
            self.send_gauge('ton.validator.efficiency', 100.0)