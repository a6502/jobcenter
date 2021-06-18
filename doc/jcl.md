# JobCenter Language

## Terminology

### Workflow

A sequence of tasks or steps to accomplish something.

### Task

A step in a workflow. A tasks can be a 'action', a 'workflow', a
'procedure' or a 'system task'.

- action
Step executed by a external worker
- workflow
A call to another workflow, creating a child-job.
- procedure
A stored procedure in the database that contains the JobCenter schema.
- 'system task'
Workflow primitives like 'if' and 'while' are implemented as 'system tasks'.

### Job

An instance of a workflow.

## Concepts

### Data Types

The recognized data types are either the the basic types of JSON or
specified using a JSON schema.

The basic types are number, string, boolean and null. The composite types
are array and oject (for a free-form JSON object).

Any other types names refer to a type specified by a JSON Schema in the
'json_schemas' table. Currently the only way to add/alter/delete types is by
direct (psql) manipulation of that table.

### Input Map

A input map copies values from the workflow state (consisting of the
arguments to the workflow, the workflow environment and the workflow state
variables) to the inputs of the called action.

A input map is a series of assignments to the (implicit) 'i' object, one per
line.  For example: "foo = v.bar" or "etwas = a.thing\[v.offset\]".  In the
right hand side expression the objects that can be referenced are 'a' for
the arguments, 'e' for the environment, 'v' for the state variables and 't'
for a temporary object.

On the left hand side the 'i' is implicit, also allowed is 't' as a place to
store temporary values. (Available for the duration of the evaluation of the
input map.)

A line of the form "&lt;foo>" is a shorthand notation for "i.foo = v.foo".

### Output Map

A output map uses the results of the called actions to modify the state
variables of the workflow, one assignment per line.  For example: "bar =
o.baz".  The 'v' on the left hand side is implicit, also allowed is 't' for
the temporary object. On the right hand side the available objects are 'o'
for the action outputs and the familiar 'a', 'e' and 't' objects.

A line of the form "&lt;foo>" is a shorthand notation for "v.foo = o.foo".

### Workflow Output Map

A workflow output map uses the workflow state to generate the workflow
outputs on completion of the workflow.  (This is what the "end" task that
every workflow has does).  The assignments are in the usuall one-per-line
format, on the left hand side the 'o' is implicit and 't' is allowed. 
Available on the right hand side are 'a', 'e','v' and 't'.

A line of the form "&lt;foo>" is a shorthand notation for "o.foo = v.foo".

### Identifier Quoting

Normal identifiers start with a alphabetic character or a underscore,
further characters can be alphanumeric or underscores. Identifiers not
following this pattern need to be quoted in single or double quotes.

Example: '2-factor' = v."2nd"

### Limits

A workflow as executed by the JobCenter has two default limits: 

- max\_steps = 100

    On every step ("state transition") of the execution of the job the
    stepcounter is incremented.  When the max\_steps value is exceeded a fatal
    error is raised.

- max\_depth = 10

    Every time that a job calls another workflow (or its own workflow) the call
    depth is incremented.  When a call causes the call depth to exceed the
    max\_depth value a fatal error is raised.

Together those two limits should give a reasonable protection from runaway
workflows due to endless loops or unbounded recursion.

### Locking

A workflow can declare exclusive locks for resources that it needs exclusive
access to.  Locks have a 'type' and a 'value', for example resp. 'domain' and
'example.com'.

Locks can be declared 'manual' when at compile time the lock value is still
unknown. A explicit lock step is then required to acquire the lock.

Locks can be inherited by child-jobs if the locks are declared with the
'inherit' option. During the execution child-jobs the parent job is
blocked waiting for those child-jobs, so it can be save to allow the
child-jobs to 'borrow' the lock, one at a time, so that access to a resource
can be co-ordinated.

All locks not declared manual are acquired at the start of the job, in the
order that they are declared. If a deadlock is detected a fatal error is
raised.

All locks are automatically released on job termination. Those that were
'borrowed' are returned to the parent.

All locks can be unlocked manually during job execution using the unlock
statement.

### Events

The JobCenter has a publish-subscribe event model.  Jobs can subscribe to
events and then later wait for those events to turn up.  Events are
referenced to by name where relevant.  Events have a 'event mask' which is
just a jsonb object that has to be contained in the event data for the event
to be recognized.

### Error Handling

Runtime errors (such as type errors of division by zero) encountered by the
JobCenter per default lead to the termination of the job with an error
object as output.  A child-job terminationg with an error will cause an
error of class childerror to be raised in the parent.

Non-fatal errors can be caught with the try-catch construction, any errors
encountered during the execution of the try-block will cause the execution
to jump to the catch-block immediately.  In the enviroment the '\_error'
object will contain information about the error.  (At least a error class
and a error message).

### Parrallel Execution

A job can create multiple child-jobs that will execute in parrallel using
the split statement.  The child-jobs are created by callflow statements in
the order specified.  After the creation of the child-jobs the parent-job
will wait for all child-jobs to terminate successfully and then execute the
output maps of the callflow statements in the order specified.

If any the child-jobs terminates with an error of class childerror will be
raised in the parent. If the error in the parent is not handled the parent
will terminate and the other child-jobs will get a abort signal.

### Perl Blocks

All expressions and assignments are compiled to Perl code that is executed
in a sandbox. All expression and assignments can be replaced with a
perl-block using the \[\[ &lt;perl> \]\] or \[&lt;delimiter>\[ &lt;perl> \]&lt;delimiter>\]
syntax. Currently perl-blocks are required for using regular expressions.

Inside a perl-block the various JSON objects are available as hashses, so
the a.input argument becomes $a{input} etc.

## Worklow

### Toplevel Elements

- workflow &lt;name>:

    Start definining a workflow of that name.

- in:

    Declare the input parameters, one per line.

        Format: <name> <type> [<default>]

    Paramaters without a default value are required.

- out:

    Declare the output parameters, one per line.

        Format: <name> <type> ['optional']

    Parameters without the 'optional' keyword are required.

- config

    Declare the workflow limits. See ["Limits"](#limits)

        Format: <limit> = <value>

- locks

    Declare the workflow locks.

        Format: <type> <value> ['manual' | 'inherit']

- role

    Specify the role that is allowed to call this workflow

- do:

    The actual workflow code goes here

- wfomap

    Declare the ["Workflow Output Map"](#workflow-output-map).

### Steps and Statements

- assert

        assert <expression>:
            <rhs>

    The expression is evaluated and when it is false an error is raised with
    the rhs as the error message.

- call

        call <name>:
            <imap>
        into:
            <omap>

    The &lt;imap> and &lt;omap> are lists of assignments. See ["Input Map"](#input-map).
    The 'into:' stanza and output map are optional when the action has no
    outputs.

- case

        case <expression>:
        when <label>:
            <block>
        else:
            <block>

    A case label is a comma-seperated list of strings.  Strings can be use
    single or double quotes.  String that are valid identifiers can be left
    unquoted.

- eval

        eval:
            <assignments>

    Alias for 'let'.

- goto

        goto <label>

    Jumps to &lt;label>. &lt;labels>s are created by ["label"](#label) statements.

- if

        if <expression>:
            <block>
        elsif <expression>:
            <block>
        else:
            <block>

- label

        label <label>

    Declare a &lt;label>, a target for goto.

- let

        let:
            <assignments>

    Alias for 'eval'.

- lock

        lock <type> <value>

    See ["Locking"](#locking)

- raise\_error

        raise_error <rhs>

- raise\_event

        raise_event:
             event = <rhs>

- repeat

        repeat:
            <block>
        until <expression>

- return

        return

    Causes immediate execution of the end task.

- sleep

        sleep <rhs>

    The rhs needs to be a valid PostgreSQL interval expression.

- split

        split:
            callflow <name1>:
                <imap>
            into:
                <omap>
           callflow <name2>:
               <imap>
           into:
               <omap>
           ...

    See ["Parrallel Execution"](#parrallel-execution)

- subscribe

        subscribe:
            name = <rhs>
            mask = <rhs>

    See ["Events"](#events)

- try

        try:
            <block>
        catch:
            <block>

    See ["Error Handling"](#error-handling)

- unlock
    unlock &lt;type> &lt;value>

    See ["Locking"](#locking)

- unsubscribe

        unsubscribe:
            name = <rhs>

- wait\_for\_event

        wait_for_event:
            events = <eventlist>
            timeout = <number>
        into:
            <omap>

- while

        while <expression>:
            <block>

## Action

### Toplevel Elements

- action &lt;name>:

    Start definining a workflow of that name.

- in:

    Declare the input parameters, one per line.

        Format: <name> <type> [<default>]

    Paramaters without a default value are required.

- out:

    Declare the output parameters, one per line.

        Format: <name> <type> ['optional']

    Parameters without the 'optional' keyword are required.

- config:

    Specify action configuration. Allowed keys:

        - filter
              Array of allowed filter keys
        - retry
              Retry policy
         - timeout
              Maximum working time
         - retryable
              Retryable flag

- role:

    Specify which role is allowed to announce this action

- env:

        Format: <name> <type> [<default>]

    Specify which values of the workflow environment are copied to the
    action environment.

