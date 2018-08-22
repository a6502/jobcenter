package JobCenter::JCC::Grammar;
use 5.10.0;
use Pegex::Base;
use base 'Pegex::Base';
extends 'Pegex::Grammar';

has indent => [];
has tabwidth => 8;
 
my $EOL = qr/\r?\n/;
my $EOD = qr/(?:$EOL)?(?=\z|\.\.\.\r?\n|\-\-\-\r?\n)/;
my $SPACE = qr/ /;
my $NONSPACE = qr/(?=[^\s\#])/;
my $NOTHING = qr//;


# based on https://metacpan.org/source/INGY/YAML-Pegex-0.0.17/lib/YAML/Pegex/Grammar.pm

# check that the indentation level increases by one step but do not consume
sub rule_block_indent_real {
	my ($self, $parser, $buffer, $pos) = @_;
	return if $pos >= length($$buffer);
	my $indents = $self->{indent};
	my $tabwidth = $self->{tabwidth};
	pos($$buffer) = $pos;
	my $len = @$indents ? $indents->[-1] + 1 : 1;
	say "need indent of at least $len";
	my ($indent) = $$buffer =~ /\G^(\s+)\S/cgm or return;
	# expand tabs
	$indent =~ s/\t/' ' x $tabwidth/eg; # todo: optimize?
	$indent = length($indent);
	say "found indent of ", $indent;
	return if $indent < $len;
	push @$indents, $indent;
	say "indents now ", join(', ', @$indents);
	return $parser->match_rule($pos);
}
 
# consume indentation and check that the indentation level is still the same
sub rule_block_ondent {
	my ($self, $parser, $buffer, $pos) = @_;
	my $indents = $self->{indent};
	my $tabwidth = $self->{tabwidth};
	my $len = $indents->[-1];
	say "need indent of $len";
	pos($$buffer) = $pos;
	my ($indent) = $$buffer =~ /\G^(\s+)(?=\S)/cgm or return; # no indent no match
	# expand tabs
	$indent =~ s/\t/' ' x $tabwidth/eg;
	$indent = length($indent);
	return if $indent != $len;
	return $parser->match_rule(pos($$buffer));
}
 
# check that the indentation level decreases by one step but do not consume
sub rule_block_undent {
	my ($self, $parser, $buffer, $pos) = @_;
	my $indents = $self->{indent};
	return unless @$indents;
	my $tabwidth = $self->{tabwidth};
	my $len = $indents->[-1];
	say "need indent of less than $len";
	pos($$buffer) = $pos;
	my ($indent) = $$buffer =~ /(?:\G^(\s*)\S)|\z/cgm; # always matches?
	if ($indent) {
		# expand tabs
		$indent =~ s/\t/' ' x $tabwidth/eg;
		$indent = length($indent);
	} else {
		$indent = 0;
	}
	say "found indent of ", $indent;
	return unless $indent < $len;
	pop @$indents;
	return $parser->match_rule($pos);
}


has text =>  <<'EOT';
%grammar wfl
%version 0.0.2

jcl: .ignorable* ( +workflow | +action ) .ignorable*

# hack in action support
action: +action-type +workflow-name colon (
	( .ignorable | +in | +out | +env | +role | +config )+
	| `syntax error: action [name]\n:<action>` )

action-type: / ( 'action' | 'procedure' ) / +

workflow: / 'workflow' + / +workflow-name colon (
	( .ignorable | +in | +out | +wfenv | +role | +config | +locks | +wfomap | +do )+
	| `syntax error: workflow [name]\n:<workflow>` )

workflow-name: identifier

in: / 'in' <colon> / ( block-indent inout block-undent
	| `syntax error: in:\n<inout>` )

env: / 'env' <colon> / ( block-indent inout block-undent
	| `syntax error: env:\n<inout>` )

out: / 'out' <colon> / ( block-indent inout block-undent
	| `syntax error: out:\n<inout>` )

inout: ( iospec | .ignorable )*

iospec: block-ondent identifier + identifier (+ / ('optional') / | + literal)? / - SEMI? - /

idlist: block-ondent identifier

config: / 'config' <colon> / ( assignments | `syntax error: config:\n<assignments>` )

wfenv: / 'wfenv' <colon> / ( assignments | `syntax error: wfenv:\n<assignments>` )

locks: / 'locks' <colon> / (
	block-indent ( lockspec | .ignorable )* block-undent
	| `syntax error: locks:\n<lockspec>` )

lockspec: block-ondent identifier  + ( identifier | / ( UNDER ) / ) (+ / ( 'inherit' | 'manual') / )*

role: / 'role' <colon> / (
	block-indent ( idlist | .ignorable )* block-undent
	| `syntax error: role:\n<idlist>` )

wfomap: / 'wfomap' <colon> / ( assignments | `syntax error: wfomap:\n<assignments>` )

do: / 'do' <colon> / ( block | `syntax error: do:\n<block>` )

# accept a comment where we expect a block-indent
block-indent: .ignorable* block-indent-real

block: block-indent block-body block-undent

block-body: (block-ondent statement | .ignorable)*

statement: 
	| +call
	| +case
	| +eval
	| +goto
	| +if
	| +label
	| +lock
	| +raise_error
	| +raise_event
	| +repeat
	| +return
	| +sleep
	| +split
	| +subscribe
	| +try
	| +unlock
	| +unsubscribe
#	| wait_for_child
	| +wait_for_event
	| +while

call: / 'call' + / +call-name colon ( call-body | `syntax error: call [name]:\n<call-body>` )

call-name: identifier

call-body: +imap block-ondent / 'into' <colon> / +omap

imap: assignments

omap: assignments

assignments: perl-block | native-assignments

native-assignments: block-indent ( assignment | magic-assignment | .ignorable )* block-undent

assignment: block-ondent lhs - assignment-operator - rhs / - SEMI? - /

magic-assignment: block-ondent / LANGLE / identifier / RANGLE /

lhs: ( / (ALPHA) DOT / )? varpart ( / DOT / varpart )*

assignment-operator: / ( EQUAL | DOT EQUAL | PLUS EQUAL | DASH EQUAL ) /

rhs: term ( rhs-operator term )*

term: +unop-term | plain-term

unop-term: unary-operator plain-term

plain-term: +functioncall | literal | +variable | +parented

parented: / LPAREN - / rhs / - RPAREN /

rhs-operator: / - ( STAR STAR | STAR | SLASH SLASH | SLASH | PERCENT | 'x' | PLUS | DASH | DOT
	| LANGLE EQUAL | RANGLE EQUAL | LANGLE | RANGLE | 'lt'
	| 'gt' | 'le' | 'ge' | EQUAL EQUAL | BANG EQUAL | 'eq' | 'ne'
	| AMP AMP | PIPE PIPE | 'and' | 'or' ) - /


unary-operator: / ( BANG | DASH | PLUS | 'not ' ) /

functioncall: identifier / LPAREN - / ( funcarg ) / - RPAREN /

funcarg: rhs ( - ( COMMA | COLON ) - rhs )*

case: / 'case' + / +case-expression colon (+when | .ignorable)* case-else?

case-expression: ( perl-block | rhs )

when: block-ondent / 'when' +  / +case-label colon +block

case-label: identifier ( - COMMA - identifier )*

case-else: block-ondent +else

eval: / 'eval' <colon> / ( assignments | `syntax error: eval:\n<assignments>` )

goto: / 'goto' + / identifier

label: / 'label' + / identifier

if: / 'if' - / ( +condition colon +then elses? | `syntax error: if <condition>:\n<if>` )

then: block

elses: block-ondent ( +elsif | +else )

elsif: / 'elsif' + / +condition colon +then elses?

else: / 'else' <colon> / block

lock: / 'lock' + / identifier + ( perl_block | rhs )

raise_error: / 'raise_error' <colon> / assignments

raise_event: / 'raise_event' <colon> / assignments

repeat: / 'repeat' colon / +block / + 'until' + / +condition

return: / ('return') /

sleep: / 'sleep' <colon> / assignments

split: / 'split' / colon block-indent callflow+ block-undent

callflow: block-ondent / 'callflow' + / +call-name colon call-body

subscribe: / 'subscribe' <colon> / assignments

try: / 'try' / colon +try-block block-ondent / 'catch' / colon +catch-block

try-block: block

catch-block: block

unlock: / 'unlock' + / identifier + ( perl_block | rhs )

unsubscribe: / 'unsubscribe' <colon> / assignments

wait_for_event: / 'wait_for_event' / colon call-body

while: / 'while' + / +condition colon +block

condition: perl-block | rhs

variable: / ( ALPHA ) DOT / varpart ( / DOT / varpart )*

varpart: identifier ( / LSQUARE <integer> LSQUARE / )?

literal: +number | +boolean | +single-quoted-string | +double-quoted-string | +null

null: / ('NULL'|'null') /

number: / ( (:'0'[xX] HEX+) | (:'-'? DIGIT* DOT DIGIT+) | (:'-'? DIGIT+) ) /

boolean: / ('TRUE'|'FALSE'|'true'|'false') /

ignorable: blank-line | multi-line-comment | single-line-comment
blank-line: / - EOL /
multi-line-comment: / - HASH LSQUARE ( ANY*? ) LSQUARE ALL*? HASH RSQUARE \1 RSQUARE /
single-line-comment: / - HASH ANY* EOL /

identifier: bare-identifier | string

bare-identifier: /( ALPHA WORD* )/

string: single-quoted-string | double-quoted-string

single_quoted_string:
    /(:
        SINGLE
        ((:
            [^ BREAK BACK SINGLE] |
            BACK SINGLE |
            BACK BACK
        )*?)
        SINGLE
    )/

double_quoted_string:
    /(:
        DOUBLE
        ((:
            [^ BREAK BACK DOUBLE] |
            BACK DOUBLE |
            BACK BACK |
            BACK escape
        )*?)
        DOUBLE
    )/

escape: / [0nt] /

perl-block: / - LSQUARE ( ANY *? ) LSQUARE ( (?: (?! RSQUARE RSQUARE ) ALL )*? ) RSQUARE \1 RSQUARE EOL? /

integer: / ( DASH? DIGIT+ ) /

unsigned-integer: / ( DIGIT+ ) /

colon: / - COLON - EOL /

# normally _ and __ matches newlines to, we don't want that?
#_: / BLANK* /
#__: / BLANK+ /
# because ingy says so:
ws: / BLANK /

EOT

sub foo {
	say 'foo!';
}

1;
