
# JobCenter JSON-RPC 2.0 API
 
## Design considerations for a 'outside' API for clients and workers of the JobCenter based on JSON RPC 2.0.

Relevant link: http://www.jsonrpc.org/specification

### Goals

*   Provide a translation from the low-level or 'native' PostgreSQL stored procedure API to something:
    *   easier to use
    *    more standards based
    *    etc?
*   Provide a mapping from some outside authentication/authorization mechanism to the internal one based on PostgreSQL roles.
    *    OAuth2?
    *    Some password database?
    * ...

### Why JSON RPC 2.0?

*   Because it is asynchronous by design
*   Because it is bidirectional by design
*   Because it is multiplexing by design
*   Because it has a concept of 'notifications' (calls without answers)
*   ...

## Transport layer

The JobCenter JSON RPC 2.0 API can work over any bidirectional transport
that has a adequate framing mechanism.  Currently implemented is the use of
either plain TCP or TLS connections with netstrings as a framing mechanism.

The default port for the API is 6522.

### Example for a client:

| JobCenter Client | JobCenter Client API |
|------------------|----------------------|
| The client opens a TCP connection to the API. |
|| The API accepts the connection and sends a 'greetings' notification. The greeting contains at least acceptable authentication methods. |
| After receipt of the greeting the client chooses a authentication method and does a 'hello' call. |
|| The API processes the 'hello' call. On success: the connection enters the 'authenticated' phase. On failure: sends a error message and closes the connection. |
| The client is now authenticated. |
| ... time passes ... ||
| The client calls 'create_job' to create a job	|
|| The API creates the job using the low level API. On success: returns the job_id. On failure: returns the error message. (example: "input parameter "i1" has wrong type string (should be number)") |
| The client stores the job_id somewhere safe and optionally continues with other things. |
| ... time passes ... ||
|| The API receives a 'job finished' notification from the low level API. |
|| The API sends a job_status(job_id, result) notification to the client. |
| The client receives the notification and continues to do marvelous things with the results |
	 
### Example for a worker:
 
| JobCenter Worker | JobCenter Worker API |
|------------------|----------------------|
| The worker opens a TCP connection to the API |
|| The API accepts the connection and sends a 'greetings' notification. The greeting contains at least acceptable authentication methods. |
| After receipt of the greeting the worker chooses a authentication method and does a 'hello' call. |
|| The API processes the 'hello' call. On success: the connection enters the 'authenticated' phase. On failure: sends a error message and then closes the connection. |
| The worker is now authenticated and calls 'announce(action)' to the the API what actions it can do. |
|| The API processes the 'announce' call by announcing the worker and action to the low level API and listening on the listenstring channel. |
| ... time passes ... ||
|| The API receives a 'action:[X]:ready' notification from the low level API and sends a 'action_ready(action, job_id)' notification to the worker. |
| If the worker is currently able (i.e. not too busy) to execute the action it calls get_task(action, job_id). |
||  The API calls the low level get_task method and returns the results to the worker. |
| If the worker actually got the task it performs the action and does a task_done notification with the results. |
|| The API calls the low level task_done method with the results |
| ... ||

## API Methods and Notifications


### greetings


Notification sent by the API on a new connection.

Params:

    who : jcapi
    version : JobCenter JSON RPC 2.0 API version, currently 1.0


### hello

Sent by clients (including workers) wishing to authenticate;

Params:

    who : who to authenticate as
    method : authentication method
    token : authentication token

Returns an error when parameters are missing.  Otherwise it returns a 2
element array.  The first element is a boolean flag indicating if
authentication succeeded.  The second element is either a welcome message or
a error message.

After a successful authentication the connection enters the 'authenticated' state. All other API methods require the connection to be in this state.

Result:

    [ flag, messsage ]


### create_job

Sent by clients wishing to create a new JobCenter job.

Params:

    wfname : name of the workflow
    inargs : JSON object with input arguments
    vtag (optional) : version tag, for example 'stable'

Returns an error when parameters are missing.  Otherwise it returns a 2
element array.  If the job was created succesfullly the first element is the
job_id and the second element is undefined. If there was an error creating
the job (probably due to missing inargs or wrongly typed inargs) the first
element is undefined and the second element is an error message.

Result:

    [ job_id, message ]


### job_done

Notification sent by the API when a job created by the client on this connection completes

Params:

    job_id
    outargs : JSON object with the results


### get_job_status

Can be used to poll the status of a job by a client.

Params:

    job_id : the job_id to query.

Returns no values if the job isn't finished. Returns the JSON object with the results if the job has finished.

Result:

    [ job_id, outargs ]


### announce

Sent by a worker to announce it is capable of a certain action.

Params:

    actionname : name of the action
    slots (optional) : amount of tasks the worker is capable of executing in parallel for this action. Defaults to 1.

Returns an error when the actionname is missing.  Otherwise returns a 2
element array.  The first element is a (boolean) success flag, the second
element is the error message.

Result:

    [ flag, "message" ]


### withdraw

Sent by a worker to announce it is no longer capable of performing a certain action.

Params:

    actionname : name of the action.

Returns an error when the actionname is missing or if the action cannot be
withdrawn because it was never announced.


### ping

Sent by the API to check that the client is still alive

Params: none

Needs to return the string 'pong' within the ping-timeout of 3 seconds.

Result:

    "pong"


### task_ready

Notification sent by the API when a task for a action the worker is capable of is available.

Params:

    actionname : actionname that has work available
    job_id : job_id of the job the task belongs to


### get_task

Sent by the worker when is it actually able to perform the task at this time.

Params:

    actionname : as announced previously
    job_id : job_id as received from task_ready

Returns no values when the task is (no longer) available.

Returns a 2 element array on success: the first element is the 'cookie' that
is a unique value so that only this worker can actually claim to have to the
task.  The second value is a JSON object with the input arguments.

Result:

    [ cookie, { json } ]


### task_done

Notification sent by the worker when is it done performing the task

Params:

    cookie : as received from get_task
    outargs: JSON object with the results

