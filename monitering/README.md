# prometheus-grafana-docker



# 1. TOTAL NUMBER OF CONTAINERS (ALL STATES)

count(container_last_seen{name!=""})


count(
  container_memory_usage_bytes{name!=""}
    and on(container)
  (time() - container_last_seen < 10)
)                                                                          -- only running containers



count(container_last_seen{instance=~"44.208.30.22:8080|44.208.30.22:9100"})








like in prometheus and grafana when we install using helm in kubernetes we have few preconfigured dashboard with nodes sperated now i am creating a dashoboard for the ec2 instances how to add a option in dashboard to give me seperate instances options and i can choose between them and i will then display the metrics of the instance which are used in the dashboard



go to varible and name instance_ip and label instance_ip


query options 

query_type classic query 

classic query  label_values(container_last_seen, instance)

regex 


/([^:]+):.*/


allow all options in selection 


count(max_over_time(container_last_seen{name!="", instance=~"${instance_ip}:.*"}[100m]))  -- list all the containers even exited in last 100min





count(
  container_memory_usage_bytes{name!="", instance=~"${instance_ip}:(8080)"}
    and on(container)
  (time() - container_last_seen < 10)
)
                                                                                        --- list all running containers