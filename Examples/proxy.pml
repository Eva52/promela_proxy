#define MAX_CLIENTS 3
#define MAX_SERVERS 3 // Change this to the number of available servers
#define TIMEOUT 500
#define CORRUPT 8080
#define DISCONNECT 404
#define MAX_REQUESTS 5

mtype = { DNS_REQUEST, DNS_RESPONSE};
chan client_to_proxy = [MAX_CLIENTS] of {int, int};
chan proxy_to_server = [MAX_CLIENTS] of {int, int};
chan server_to_proxy = [MAX_CLIENTS] of {int, int};
chan proxy_to_client = [MAX_CLIENTS] of {int, int};
chan dns_to_server = [MAX_SERVERS] of {mtype, int};
chan server_to_dns = [MAX_SERVERS] of {mtype, int};
chan dns_to_proxy = [MAX_CLIENTS] of {int, int};
chan proxy_to_dns = [MAX_CLIENTS] of {int, int};

int proxy_addr;

int last_req = 0; // last request server

int client_resource_owner[MAX_CLIENTS];
int all_server_index[MAX_SERVERS];

bool client_connection = false; // client connection flag
bool server_connection = false; // server connection flag
bool dns_connection = false; // dns conneciton flag

ltl p1 {(<>(Server@cor)->(<>(Thread@resend)))}
ltl p2 {(<>(Server@disconn)->(<>(Client@disconn)))}


proctype Client() {
    int client_req;
    int server_resp;
    int req_count = 0;
    do
      :: req_count >= MAX_REQUESTS ->
          break;
      :: else -> 
          req_count = req_count + 1
          client_req = _pid; 
          if
              :: nfull(client_to_proxy) ->
                  client_to_proxy ! proxy_addr, client_req;
  accept:         proxy_to_client ?? eval(_pid), server_resp;
                  assert(server_resp!=CORRUPT)
                  if
                  ::server_resp!=DISCONNECT->skip;
 disconn:         ::else->skip;
                  fi;
                  int j = 0;
                  for (j : 0..2){
                    client_resource_owner[j] == _pid ->
                      client_resource_owner[j]=0;
                  }
          fi;
    od;
}


proctype Server() {
    int dns_resp;
    int server_resp;
    int proxy_req;
    int p = 0;
    byte resource_owner;
    resource_owner = 0;

      do
      :: true ->     
end:      if
          :: proxy_to_server ?? [eval(_pid), proxy_req] ->
              assert(resource_owner == 0); // ensure mutual exclusive use
              resource_owner = _pid;
              proxy_to_server ?? eval(_pid), proxy_req;
              // Simulate server processing by generating a response
              if 
              :: (p%5) != 0 && (p%3) != 0-> server_resp = _pid;
disconn:              :: (p%3) ==3 -> server_resp = DISCONNECT;
cor:          :: else -> server_resp = CORRUPT;
              fi;
              server_to_proxy ! proxy_req, server_resp;
              resource_owner = 0;
              p++;   
          fi;
      od;
}

proctype DNS() {
    int server_index;
    server_index = 0;
    int dns_response;
    int next_index;
    int proxy_req;

      do
      :: true -> 
end:        if
            :: nempty(proxy_to_dns) ->
                proxy_to_dns ? 5500, proxy_req;
                server_index = all_server_index[next_index % MAX_SERVERS];
                next_index++;
                dns_to_proxy ! proxy_req, server_index;
                // Cycle through servers
          fi;
      od;
}
proctype Thread (int client_req){
      int server_resp = -1;
      int server_index = 0;
  
      // Simulate DNS request to get server IP
      proxy_to_dns ! 5500, _pid;
      dns_to_proxy ? eval(_pid), server_index;

      //printf("client_connection = %d, server_connection = %d\n", client_connection, server_connection);
      assert(client_connection == true)
L1:   proxy_to_server ! server_index, _pid;
      server_to_proxy ? eval(_pid), server_resp;
      if
      :: server_resp!=CORRUPT -> skip;
resend:      :: else -> goto L1;
      fi;
      server_connection = true;  

      // prevent consecutive query to the same server
      assert(last_req != server_resp); 

      proxy_to_client ! client_req, server_resp;
      if
      :: (server_resp != -1)->
        last_req = server_resp; // update server being reached
      fi;
}
proctype Proxy() {
    int client_req;
    do
    :: true -> 
end:      if
        :: nempty(client_to_proxy) ->
            client_to_proxy ? eval(_pid), client_req;
            client_connection = true;
            bool request_processing = false;
            int i = 0;
            do
              :: i < 3 && client_resource_owner[i] == client_req ->
                  request_processing = true;
                  break;
              :: i < 3 && client_resource_owner[i] != client_req->
                  i++;
              :: else ->
                break;
            od;
            assert(!request_processing);
            int j = 0;
            do
              :: j < 3 && client_resource_owner[j] == 0 ->
                  client_resource_owner[j]=client_req;
                  break;
              :: j < 3 && client_resource_owner[j] != 0->
                  j++;
              :: else ->
                  j=0;
            od;
            
            run Thread (client_req);
        fi;
    od;
}

init{	
  atomic{
    int i = 0;
    do
      :: i < 3 ->
          client_resource_owner[i] = 0;
          run Client();
          all_server_index[i]=run Server();
          i++;
      :: else ->
          break;
    od;
    run DNS();
    proxy_addr=run Proxy();
  }
}