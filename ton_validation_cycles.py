import sys
sys.path.append("/usr/src/mytonctrl")
sys.path.append("/usr/local/lib/python3.8/dist-packages/")
import mytonctrl
import mytoncore

LAST_KNOWN_INACTIVE_CYCLE_START_TIME = 1649841799
CYCLE_LENGTH = 65536

# the following try/except block will make the custom check compatible with any Agent version
try:
    # first, try to import the base class from new versions of the Agent...
    from datadog_checks.base import AgentCheck
except ImportError:
    # ...if the above failed, the check is running in Agent version < 6.6.0
    from checks import AgentCheck

# content of the special variable __version__ will be shown in the Agent status page
__version__ = "1.0.0"

class ValidatorEfficiencyCheck(AgentCheck):
    def send_count(self, value):
         self.count('ton.validator.cycles', value, tags=['SERVICE:ton'] + self.instance.get('tags', []))

    def check(self, instance):
        mytoncore.local.buffer["localdbFileName"] = "/usr/local/bin/mytoncore/mytoncore.db"
        toncore = mytonctrl.MyTonCore()
        toncore.liteClient.configPath = "/usr/src/validator-monitoring/local.config.json"
        mytoncore.local.db["liteServers"] = [0]
        fullElectorAddr = toncore.GetFullElectorAddr()
        startWorkTime = toncore.GetActiveElectionId(fullElectorAddr)
        if startWorkTime == 0:
            startWorkTime = toncore.GetConfig36().get("startWorkTime")
        if startWorkTime is None:
            startWorkTime = toncore.GetConfig34().get("startWorkTime")
        cyclesAfterInactive = (startWorkTime - LAST_KNOWN_INACTIVE_CYCLE_START_TIME) / CYCLE_LENGTH
        if (int(cyclesAfterInactive) % 2) != 0:
            # odd number of cycles after last known inactive cycle
            if len(list(filter(lambda v: v["adnlAddr"] == toncore.adnlAddr, toncore.GetConfig34()["validators"]))) != 0:
                self.send_count(0)
            else:
                self.send_count(1)
        else:
            self.send_count(0)
