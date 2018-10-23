
# JobCenter Error Handling

The JobCenter has various levels of error handling to make live easier.

## Errors have class

A JobCenter level error has an 'error class'. If no class is specified the
class is 'default'. Currently there are only 2 error classes that have
a special meaning: 'fatal' and 'soft'.

## Fatal Errors

Errors of this class lead to immediate termination of the job. Causes are
workflow level limits that are exceeded, such as the maximum number of
workflow steps or the maximum call depth.

## Soft Errors

Soft errors are errors that can be retried automatically on the action level
if a suitable retry policy exists. See 'Action level error handling' below.

## Error reporting by the JobCenter

A JobCenter client receives the results of a job as a JSON object.  If the
only top-level key in that object is 'error' there was an error.  The value
can either be a string containing the error message or another object
containing more elaborate error information.  At least there will be a key
'msg' containing an error message.  A key 'class' may indicate the error
class.

## Error reporting by a worker

A worker can signal an error by returning an error object as described
above. A error class of 'soft' willt trigger action level error handling,
when available.

## Error detection by the JobCenter

-   If a worker disconnects or has a ping timeout all actions that have
    configuration option 'restartable' set to true will automatically have a
    'soft' error raised, triggering action level error handling.

-   If a action has a 'timeout' configuration option set and if a worker has
    been working on this action for this job longer than that timeout a soft
    error will be raised.

## Action Level Error Handling

If a job enters a 'soft' error state while processing an action the
JobCenter will look for a 'retry policy' in the action configuration. If
present the action will automatically retried after a 'interval' waiting
period for a maximum of 'tries' times. If tries is &lt; 0 the action will
be retried until it succeeds. After 'tries' times a workflow level error
will be raised.

## Workflow Level Error Handling

Runtime errors (such as type errors of division by zero) encountered by the
JobCenter per default lead to the termination of the job with an error
object as output.  A child-job terminationg with an error will cause an
error of class childerror to be raised in the parent.

Non-fatal errors can be caught with the try-catch construction, any errors
encountered during the execution of the try-block will cause the execution
to jump to the catch-block immediately.  In the enviroment the '\_error'
object will contain information about the error.  (At least a error class
and a error message).

