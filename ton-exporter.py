from prometheus_client import REGISTRY, PROCESS_COLLECTOR, PLATFORM_COLLECTOR
from prometheus_client import Gauge
from prometheus_client import start_http_server
from multiprocessing import Process, Queue
import subprocess
import tempfile
import datetime
import logging
import os
import re
import sys
sys.path.append("/usr/src/validator-monitoring")
from common import get_environment, LOCAL_CONFIG_PATH
from mytoncore.mytoncore import MyTonCore
from mypylib.mypylib import MyPyClass
from time import sleep

logging.basicConfig(format='%(levelname)s:%(message)s', level=logging.DEBUG)


REGISTRY.unregister(PROCESS_COLLECTOR)
REGISTRY.unregister(PLATFORM_COLLECTOR)
REGISTRY.unregister(REGISTRY._names_to_collectors['python_gc_objects_collected_total'])

mytoncore_local = MyPyClass('mytoncore.py')
toncore = MyTonCore(mytoncore_local)
toncore.local.db.config.logLevel = "error"
toncore.local.db.config.isIgnorLogWarning = True
toncore.liteClient.configPath = LOCAL_CONFIG_PATH
toncore.local.db.liteServers = [0]

start_http_server(8000, addr='127.0.0.1')

TRIVIAL_HEALTH_IDENTIFICATIOPN_STRING = 'latest masterchain block known to server is'
UNIX_TIME_RE = re.compile('(?:' + TRIVIAL_HEALTH_IDENTIFICATIOPN_STRING + ' .*created at )(\d{10})')
DB_PATH = "/var/ton-work/db"
COLLECTION_INTERVAL = 15

def process_logs():
    import inspect
    parentframe = inspect.stack()[1][0]
    module = inspect.getmodule(parentframe)
    metric_name = getattr(module, parentframe.f_code.co_name).__doc__
    logging.info("Running %s check.", metric_name)
    toncore.local.db.config.logLevel = "info"

def efficiency(q, tonc):
    '''ton_validator_efficiency'''
    process_logs()
    if len(list(filter(lambda v: v["adnlAddr"] == tonc.GetAdnlAddr(), tonc.GetConfig34()["validators"]))) != 0:
        q.put(tonc.GetValidatorEfficiency(adnlAddr=tonc.GetAdnlAddr()))
        return
    q.put(100)

def index(q, tonc):
    '''ton_validator_index'''
    process_logs()
    if len(list(filter(lambda v: v["adnlAddr"] == tonc.GetAdnlAddr(), tonc.GetConfig34()["validators"]))) != 0:
        q.put(tonc.GetValidatorIndex(adnlAddr=tonc.GetAdnlAddr()))
        #raise Exception()
        return
    q.put(None)

def replication_lag(q, tonc):
    '''ton_replication_lag'''
    process_logs()
    output = error = exit_code = None
    try:
        process = subprocess.Popen(
                ['/usr/bin/ton/lite-client/lite-client', '-C', LOCAL_CONFIG_PATH, '-c', 'last'],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                encoding='utf8'
        )
        # huge timeout is for case of very high CPU load
        output,error = process.communicate(timeout=2)
        exit_code = process.wait(timeout=2)
    except Exception as e:
        logging.error("Got error during communication with lite-client binary:")
        logging.error(e)
    if output:
        last_line = output.rstrip().splitlines()[-1]
        if TRIVIAL_HEALTH_IDENTIFICATIOPN_STRING not in last_line:
            logging.error("Unexpexted output from lite-client.")
        else:
            unix_time_match = UNIX_TIME_RE.match(last_line)
            if not unix_time_match:
                logging.error("Got output from lite-client, but format is unexpexted.")
            else:
                matched_groups = unix_time_match.groups()
                if not matched_groups:
                    logging.error("Somehow the output matched regex, but we got emty groups tuple")
                else:
                    unix_time_str = matched_groups[0]
                    # we have ONLY digits now and quantity of them is strictly 10, so no need o make extra validations

                    ts = datetime.datetime.utcfromtimestamp(int(unix_time_str))
                    now = datetime.datetime.utcnow()
                    diff = now - ts
                    q.put(diff.total_seconds())

    else:
        logging.error("Got zero output from lite-lient.")

    if error and exit_code != 0:
        logging.error(error.strip())
        if output:
            logging.error(output)
    q.put(None)

class FakeStatResult:
    st_size = 0
    st_blocks = 0
    st_ino = 0

def os_lstat_wrapped(path):
    try:
        return os.lstat(path)
    except FileNotFoundError:
        # Between os.path.islink() and os.lstat() calls file could be deleted.
        # No way to go atomic here.
        return FakeStatResult()

def db_size(q, tonc):
    '''ton_db_size'''
    process_logs()
    total_bytes = 0
    have = []
    for dirpath, dirnames, filenames in os.walk(DB_PATH):
        total_bytes += os_lstat_wrapped(dirpath).st_blocks * 512
        for f in filenames:
            fp = os.path.join(dirpath, f)
            if os.path.islink(fp):
                continue
            st = os_lstat_wrapped(fp)
            if st.st_ino in have:
                continue  # skip hardlinks which were already counted
            have.append(st.st_ino)
            total_bytes += st.st_blocks * 512
        for d in dirnames:
            dp = os.path.join(dirpath, d)
            if os.path.islink(dp):
                apparent_total_bytes += os_lstat_wrapped(dp).st_size
    q.put(total_bytes)

METRIC_FUNCS = [efficiency, index, replication_lag, db_size]

def unregister_if_exists(metric_name):
    print(metric_name)
    if REGISTRY._names_to_collectors.get(metric_name, None) is not None:
         REGISTRY.unregister(REGISTRY._names_to_collectors[metric_name])

while True:
    #process_to_queue_and_metric_name = {}
    process_data = {}
    for metric_func in METRIC_FUNCS:
        queue = Queue()
        p = Process(target=metric_func, args=(queue, toncore))
        p.start()
        process_data[p] = {"queue": queue, "metric_name": metric_func.__doc__}
        #process_to_queue_and_metric_name[p] = (queue, metric_func.__doc__)
    for p, data in process_data.items():
        queue = data["queue"]
        metric_name = data["metric_name"]
        #queue, metric_name = queue_and_metric_name
        p.join(timeout=60)
        if p.exitcode == 0:
            result = queue.get()
            if result is not None:
                g = REGISTRY._names_to_collectors.get(metric_name, None)
                if g is None:
                    g = Gauge(metric_name, "no description", labelnames=["environment", "service", "instance"])
                g.labels(service="ton", environment=get_environment(), instance=os.uname()[1]).set(result)
                logging.info("Got success running %s check.", metric_name)
            else:
                logging.info("Check %s returned none. Valishing from registry.", metric_name)
                unregister_if_exists(metric_name)
        else:
            p.terminate()
            logging.info("Check %s got non-zero exit code. Probably exception occured.  Valishing from registry.", metric_name)
            unregister_if_exists(metric_name)
        # by default the temporary file is deleted as soon as it is closed
    sleep(COLLECTION_INTERVAL)
