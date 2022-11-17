log_suffix=`date +"%Y%m%d%H%M%S"`
$CONFLUENT_HOME/bin/connect-distributed $CONFLUENT_HOME/etc/kafka/connect-distributed.properties 2>&1 | tee -a ~/connect_console_log/connect_console_$log_suffix.log
