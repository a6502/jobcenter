package JobCenter::JCC::Grammar;
use 5.10.0;
use Pegex::Base;
use base 'Pegex::Base';
extends 'Pegex::Grammar';

use constant file => 'share/jjc.pgx';

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

# NOTE: To recompile this after changing the jjc.pgx file, run:
#
#   perl -Ilib -MJobCenter::JCC::Grammar=compile

sub make_tree {   # Generated/Inlined by Pegex::Grammar (0.64)
  {
    '+grammar' => 'wfl',
    '+toprule' => 'jcl',
    '+version' => '0.0.2',
    'COLON' => {
      '.rgx' => qr/\G:/
    },
    'COMMA' => {
      '.rgx' => qr/\G,/
    },
    '_' => {
      '.rgx' => qr/\G[\ \t]*/
    },
    '__' => {
      '.rgx' => qr/\G[\ \t]+/
    },
    'action' => {
      '.all' => [
        {
          '-wrap' => 1,
          '.ref' => 'action_type'
        },
        {
          '-wrap' => 1,
          '.ref' => 'workflow_name'
        },
        {
          '.ref' => 'colon'
        },
        {
          '.any' => [
            {
              '+min' => 1,
              '.any' => [
                {
                  '-skip' => 1,
                  '.ref' => 'ignorable'
                },
                {
                  '-wrap' => 1,
                  '.ref' => 'in'
                },
                {
                  '-wrap' => 1,
                  '.ref' => 'out'
                },
                {
                  '-wrap' => 1,
                  '.ref' => 'env'
                },
                {
                  '-wrap' => 1,
                  '.ref' => 'role'
                },
                {
                  '-wrap' => 1,
                  '.ref' => 'config'
                }
              ]
            },
            {
              '.err' => 'syntax error: action [name]\\n:<action>'
            }
          ]
        }
      ]
    },
    'action_type' => {
      '.all' => [
        {
          '.rgx' => qr/\G(action|procedure)/
        },
        {
          '.ref' => '__'
        }
      ]
    },
    'assignment' => {
      '.all' => [
        {
          '.ref' => 'block_ondent'
        },
        {
          '.ref' => 'lhs'
        },
        {
          '.ref' => '_'
        },
        {
          '.ref' => 'assignment_operator'
        },
        {
          '.ref' => '_'
        },
        {
          '.ref' => 'rhs'
        },
        {
          '.rgx' => qr/\G[\ \t]*;?[\ \t]*/
        }
      ]
    },
    'assignment_operator' => {
      '.rgx' => qr/\G(=|\.=|\+=|\-=)/
    },
    'assignments' => {
      '.any' => [
        {
          '.ref' => 'perl_block'
        },
        {
          '.ref' => 'native_assignments'
        }
      ]
    },
    'bare_identifier' => {
      '.rgx' => qr/\G([a-zA-Z]\w*)/
    },
    'blank_line' => {
      '.rgx' => qr/\G[\ \t]*\r?\n/
    },
    'block' => {
      '.all' => [
        {
          '.ref' => 'block_indent'
        },
        {
          '.ref' => 'block_body'
        },
        {
          '.ref' => 'block_undent'
        }
      ]
    },
    'block_body' => {
      '+min' => 0,
      '.any' => [
        {
          '.all' => [
            {
              '.ref' => 'block_ondent'
            },
            {
              '.ref' => 'statement'
            }
          ]
        },
        {
          '-skip' => 1,
          '.ref' => 'ignorable'
        }
      ]
    },
    'block_indent' => {
      '.all' => [
        {
          '+min' => 0,
          '-skip' => 1,
          '.ref' => 'ignorable'
        },
        {
          '.ref' => 'block_indent_real'
        }
      ]
    },
    'boolean' => {
      '.rgx' => qr/\G(TRUE|FALSE|true|false)/
    },
    'call' => {
      '.all' => [
        {
          '.rgx' => qr/\Gcall[\ \t]+/
        },
        {
          '-wrap' => 1,
          '.ref' => 'call_name'
        },
        {
          '.ref' => 'colon'
        },
        {
          '.any' => [
            {
              '.ref' => 'call_body'
            },
            {
              '.err' => 'syntax error: call [name]:\\n<call-body>'
            }
          ]
        }
      ]
    },
    'call_body' => {
      '.all' => [
        {
          '-wrap' => 1,
          '.ref' => 'imap'
        },
        {
          '.ref' => 'block_ondent'
        },
        {
          '.rgx' => qr/\Ginto[\ \t]*:[\ \t]*\r?\n/
        },
        {
          '-wrap' => 1,
          '.ref' => 'omap'
        }
      ]
    },
    'call_name' => {
      '.ref' => 'identifier'
    },
    'callflow' => {
      '.all' => [
        {
          '.ref' => 'block_ondent'
        },
        {
          '.rgx' => qr/\Gcallflow[\ \t]+/
        },
        {
          '-wrap' => 1,
          '.ref' => 'call_name'
        },
        {
          '.ref' => 'colon'
        },
        {
          '.ref' => 'call_body'
        }
      ]
    },
    'case' => {
      '.all' => [
        {
          '.rgx' => qr/\Gcase[\ \t]+/
        },
        {
          '-wrap' => 1,
          '.ref' => 'case_expression'
        },
        {
          '.ref' => 'colon'
        },
        {
          '+min' => 0,
          '.any' => [
            {
              '-wrap' => 1,
              '.ref' => 'when'
            },
            {
              '-skip' => 1,
              '.ref' => 'ignorable'
            }
          ]
        },
        {
          '+max' => 1,
          '.ref' => 'case_else'
        }
      ]
    },
    'case_else' => {
      '.all' => [
        {
          '.ref' => 'block_ondent'
        },
        {
          '-wrap' => 1,
          '.ref' => 'else'
        }
      ]
    },
    'case_expression' => {
      '.any' => [
        {
          '.ref' => 'perl_block'
        },
        {
          '.ref' => 'rhs'
        }
      ]
    },
    'case_label' => {
      '.all' => [
        {
          '.ref' => 'identifier'
        },
        {
          '+min' => 0,
          '.all' => [
            {
              '.ref' => '_'
            },
            {
              '.ref' => 'COMMA'
            },
            {
              '.ref' => '_'
            },
            {
              '.ref' => 'identifier'
            }
          ]
        }
      ]
    },
    'catch_block' => {
      '.ref' => 'block'
    },
    'colon' => {
      '.rgx' => qr/\G[\ \t]*:[\ \t]*\r?\n/
    },
    'condition' => {
      '.any' => [
        {
          '.ref' => 'perl_block'
        },
        {
          '.ref' => 'rhs'
        }
      ]
    },
    'config' => {
      '.all' => [
        {
          '.rgx' => qr/\Gconfig[\ \t]*:[\ \t]*\r?\n/
        },
        {
          '.any' => [
            {
              '.ref' => 'assignments'
            },
            {
              '.err' => 'syntax error: config:\\n<assignments>'
            }
          ]
        }
      ]
    },
    'do' => {
      '.all' => [
        {
          '.rgx' => qr/\Gdo[\ \t]*:[\ \t]*\r?\n/
        },
        {
          '.any' => [
            {
              '.ref' => 'block'
            },
            {
              '.err' => 'syntax error: do:\\n<block>'
            }
          ]
        }
      ]
    },
    'double_quoted_string' => {
      '.rgx' => qr/\G(?:"((?:[^\n\\"]|\\"|\\\\|\\[0nt])*?)")/
    },
    'else' => {
      '.all' => [
        {
          '.rgx' => qr/\Gelse[\ \t]*:[\ \t]*\r?\n/
        },
        {
          '.ref' => 'block'
        }
      ]
    },
    'elses' => {
      '.all' => [
        {
          '.ref' => 'block_ondent'
        },
        {
          '.any' => [
            {
              '-wrap' => 1,
              '.ref' => 'elsif'
            },
            {
              '-wrap' => 1,
              '.ref' => 'else'
            }
          ]
        }
      ]
    },
    'elsif' => {
      '.all' => [
        {
          '.rgx' => qr/\Gelsif[\ \t]+/
        },
        {
          '-wrap' => 1,
          '.ref' => 'condition'
        },
        {
          '.ref' => 'colon'
        },
        {
          '-wrap' => 1,
          '.ref' => 'then'
        },
        {
          '+max' => 1,
          '.ref' => 'elses'
        }
      ]
    },
    'env' => {
      '.all' => [
        {
          '.rgx' => qr/\Genv[\ \t]*:[\ \t]*\r?\n/
        },
        {
          '.any' => [
            {
              '.all' => [
                {
                  '.ref' => 'block_indent'
                },
                {
                  '.ref' => 'inout'
                },
                {
                  '.ref' => 'block_undent'
                }
              ]
            },
            {
              '.err' => 'syntax error: env:\\n<inout>'
            }
          ]
        }
      ]
    },
    'eval' => {
      '.all' => [
        {
          '.rgx' => qr/\Geval[\ \t]*:[\ \t]*\r?\n/
        },
        {
          '.any' => [
            {
              '.ref' => 'assignments'
            },
            {
              '.err' => 'syntax error: eval:\\n<assignments>'
            }
          ]
        }
      ]
    },
    'funcarg' => {
      '.all' => [
        {
          '.ref' => 'rhs'
        },
        {
          '+min' => 0,
          '.all' => [
            {
              '.ref' => '_'
            },
            {
              '.any' => [
                {
                  '.ref' => 'COMMA'
                },
                {
                  '.ref' => 'COLON'
                }
              ]
            },
            {
              '.ref' => '_'
            },
            {
              '.ref' => 'rhs'
            }
          ]
        }
      ]
    },
    'functioncall' => {
      '.all' => [
        {
          '.ref' => 'identifier'
        },
        {
          '.rgx' => qr/\G\([\ \t]*/
        },
        {
          '.ref' => 'funcarg'
        },
        {
          '.rgx' => qr/\G[\ \t]*\)/
        }
      ]
    },
    'goto' => {
      '.all' => [
        {
          '.rgx' => qr/\Ggoto[\ \t]+/
        },
        {
          '.ref' => 'identifier'
        }
      ]
    },
    'identifier' => {
      '.any' => [
        {
          '.ref' => 'bare_identifier'
        },
        {
          '.ref' => 'string'
        }
      ]
    },
    'idlist' => {
      '.all' => [
        {
          '.ref' => 'block_ondent'
        },
        {
          '.ref' => 'identifier'
        }
      ]
    },
    'if' => {
      '.all' => [
        {
          '.rgx' => qr/\Gif[\ \t]*/
        },
        {
          '.any' => [
            {
              '.all' => [
                {
                  '-wrap' => 1,
                  '.ref' => 'condition'
                },
                {
                  '.ref' => 'colon'
                },
                {
                  '-wrap' => 1,
                  '.ref' => 'then'
                },
                {
                  '+max' => 1,
                  '.ref' => 'elses'
                }
              ]
            },
            {
              '.err' => 'syntax error: if <condition>:\\n<if>'
            }
          ]
        }
      ]
    },
    'ignorable' => {
      '.any' => [
        {
          '.ref' => 'blank_line'
        },
        {
          '.ref' => 'multi_line_comment'
        },
        {
          '.ref' => 'single_line_comment'
        }
      ]
    },
    'imap' => {
      '.ref' => 'assignments'
    },
    'in' => {
      '.all' => [
        {
          '.rgx' => qr/\Gin[\ \t]*:[\ \t]*\r?\n/
        },
        {
          '.any' => [
            {
              '.all' => [
                {
                  '.ref' => 'block_indent'
                },
                {
                  '.ref' => 'inout'
                },
                {
                  '.ref' => 'block_undent'
                }
              ]
            },
            {
              '.err' => 'syntax error: in:\\n<inout>'
            }
          ]
        }
      ]
    },
    'inout' => {
      '+min' => 0,
      '.any' => [
        {
          '.ref' => 'iospec'
        },
        {
          '-skip' => 1,
          '.ref' => 'ignorable'
        }
      ]
    },
    'iospec' => {
      '.all' => [
        {
          '.ref' => 'block_ondent'
        },
        {
          '.ref' => 'identifier'
        },
        {
          '.ref' => '__'
        },
        {
          '.ref' => 'identifier'
        },
        {
          '+max' => 1,
          '.any' => [
            {
              '.all' => [
                {
                  '.ref' => '__'
                },
                {
                  '.rgx' => qr/\G(optional)/
                }
              ]
            },
            {
              '.all' => [
                {
                  '.ref' => '__'
                },
                {
                  '.ref' => 'literal'
                }
              ]
            }
          ]
        },
        {
          '.rgx' => qr/\G[\ \t]*;?[\ \t]*/
        }
      ]
    },
    'jcl' => {
      '.all' => [
        {
          '+min' => 0,
          '-skip' => 1,
          '.ref' => 'ignorable'
        },
        {
          '.any' => [
            {
              '-wrap' => 1,
              '.ref' => 'workflow'
            },
            {
              '-wrap' => 1,
              '.ref' => 'action'
            }
          ]
        },
        {
          '+min' => 0,
          '-skip' => 1,
          '.ref' => 'ignorable'
        }
      ]
    },
    'label' => {
      '.all' => [
        {
          '.rgx' => qr/\Glabel[\ \t]+/
        },
        {
          '.ref' => 'identifier'
        }
      ]
    },
    'lhs' => {
      '.all' => [
        {
          '+max' => 1,
          '.rgx' => qr/\G(ALPHA)\./
        },
        {
          '.ref' => 'varpart'
        },
        {
          '+min' => 0,
          '.all' => [
            {
              '.rgx' => qr/\G\./
            },
            {
              '.ref' => 'varpart'
            }
          ]
        }
      ]
    },
    'literal' => {
      '.any' => [
        {
          '-wrap' => 1,
          '.ref' => 'number'
        },
        {
          '-wrap' => 1,
          '.ref' => 'boolean'
        },
        {
          '-wrap' => 1,
          '.ref' => 'single_quoted_string'
        },
        {
          '-wrap' => 1,
          '.ref' => 'double_quoted_string'
        },
        {
          '-wrap' => 1,
          '.ref' => 'null'
        }
      ]
    },
    'lock' => {
      '.all' => [
        {
          '.rgx' => qr/\Glock[\ \t]+/
        },
        {
          '.ref' => 'identifier'
        },
        {
          '.ref' => '__'
        },
        {
          '.any' => [
            {
              '.ref' => 'perl_block'
            },
            {
              '.ref' => 'rhs'
            }
          ]
        }
      ]
    },
    'locks' => {
      '.all' => [
        {
          '.rgx' => qr/\Glocks[\ \t]*:[\ \t]*\r?\n/
        },
        {
          '.any' => [
            {
              '.all' => [
                {
                  '.ref' => 'block_indent'
                },
                {
                  '+min' => 0,
                  '.any' => [
                    {
                      '.ref' => 'lockspec'
                    },
                    {
                      '-skip' => 1,
                      '.ref' => 'ignorable'
                    }
                  ]
                },
                {
                  '.ref' => 'block_undent'
                }
              ]
            },
            {
              '.err' => 'syntax error: locks:\\n<lockspec>'
            }
          ]
        }
      ]
    },
    'lockspec' => {
      '.all' => [
        {
          '.ref' => 'block_ondent'
        },
        {
          '.ref' => 'identifier'
        },
        {
          '.ref' => '__'
        },
        {
          '.any' => [
            {
              '.ref' => 'identifier'
            },
            {
              '.rgx' => qr/\G(_)/
            }
          ]
        },
        {
          '+min' => 0,
          '.all' => [
            {
              '.ref' => '__'
            },
            {
              '.rgx' => qr/\G(inherit|manual)/
            }
          ]
        }
      ]
    },
    'magic_assignment' => {
      '.all' => [
        {
          '.ref' => 'block_ondent'
        },
        {
          '.rgx' => qr/\G</
        },
        {
          '.ref' => 'identifier'
        },
        {
          '.rgx' => qr/\G\>/
        }
      ]
    },
    'multi_line_comment' => {
      '.rgx' => qr/\G[\ \t]*\#\[(.*?)\[[\s\S]*?\#\]\1\]/
    },
    'native_assignments' => {
      '.all' => [
        {
          '.ref' => 'block_indent'
        },
        {
          '+min' => 0,
          '.any' => [
            {
              '.ref' => 'assignment'
            },
            {
              '.ref' => 'magic_assignment'
            },
            {
              '-skip' => 1,
              '.ref' => 'ignorable'
            }
          ]
        },
        {
          '.ref' => 'block_undent'
        }
      ]
    },
    'null' => {
      '.rgx' => qr/\G(NULL|null)/
    },
    'number' => {
      '.rgx' => qr/\G((?:0[xX][0-9a-fA-F]+)|(?:\-?[0-9]*\.[0-9]+)|(?:\-?[0-9]+))/
    },
    'omap' => {
      '.ref' => 'assignments'
    },
    'out' => {
      '.all' => [
        {
          '.rgx' => qr/\Gout[\ \t]*:[\ \t]*\r?\n/
        },
        {
          '.any' => [
            {
              '.all' => [
                {
                  '.ref' => 'block_indent'
                },
                {
                  '.ref' => 'inout'
                },
                {
                  '.ref' => 'block_undent'
                }
              ]
            },
            {
              '.err' => 'syntax error: out:\\n<inout>'
            }
          ]
        }
      ]
    },
    'parented' => {
      '.all' => [
        {
          '.rgx' => qr/\G\([\ \t]*/
        },
        {
          '.ref' => 'rhs'
        },
        {
          '.rgx' => qr/\G[\ \t]*\)/
        }
      ]
    },
    'perl_block' => {
      '.rgx' => qr/\G[\ \t]*\[(.*?)\[((?:(?!\]\])[\s\S])*?)\]\1\]\r?\n?/
    },
    'plain_term' => {
      '.any' => [
        {
          '-wrap' => 1,
          '.ref' => 'functioncall'
        },
        {
          '.ref' => 'literal'
        },
        {
          '-wrap' => 1,
          '.ref' => 'variable'
        },
        {
          '-wrap' => 1,
          '.ref' => 'parented'
        }
      ]
    },
    'raise_error' => {
      '.all' => [
        {
          '.rgx' => qr/\Graise_error[\ \t]*:[\ \t]*\r?\n/
        },
        {
          '.ref' => 'assignments'
        }
      ]
    },
    'raise_event' => {
      '.all' => [
        {
          '.rgx' => qr/\Graise_event[\ \t]*:[\ \t]*\r?\n/
        },
        {
          '.ref' => 'assignments'
        }
      ]
    },
    'repeat' => {
      '.all' => [
        {
          '.rgx' => qr/\Grepeat[\ \t]*:[\ \t]*\r?\n/
        },
        {
          '-wrap' => 1,
          '.ref' => 'block'
        },
        {
          '.rgx' => qr/\G[\ \t]+until[\ \t]+/
        },
        {
          '-wrap' => 1,
          '.ref' => 'condition'
        }
      ]
    },
    'return' => {
      '.rgx' => qr/\G(return)/
    },
    'rhs' => {
      '.all' => [
        {
          '.ref' => 'term'
        },
        {
          '+min' => 0,
          '.all' => [
            {
              '.ref' => 'rhs_operator'
            },
            {
              '.ref' => 'term'
            }
          ]
        }
      ]
    },
    'rhs_operator' => {
      '.rgx' => qr/\G[\ \t]*(\*\*|\*|\/\/|\/|%|x|\+|\-|\.|<=|\>=|<|\>|lt|gt|le|ge|==|!=|eq|ne|&&|\|\||and|or)[\ \t]*/
    },
    'role' => {
      '.all' => [
        {
          '.rgx' => qr/\Grole[\ \t]*:[\ \t]*\r?\n/
        },
        {
          '.any' => [
            {
              '.all' => [
                {
                  '.ref' => 'block_indent'
                },
                {
                  '+min' => 0,
                  '.any' => [
                    {
                      '.ref' => 'idlist'
                    },
                    {
                      '-skip' => 1,
                      '.ref' => 'ignorable'
                    }
                  ]
                },
                {
                  '.ref' => 'block_undent'
                }
              ]
            },
            {
              '.err' => 'syntax error: role:\\n<idlist>'
            }
          ]
        }
      ]
    },
    'single_line_comment' => {
      '.rgx' => qr/\G[\ \t]*\#.*\r?\n/
    },
    'single_quoted_string' => {
      '.rgx' => qr/\G(?:'((?:[^\n\\']|\\'|\\\\)*?)')/
    },
    'sleep' => {
      '.all' => [
        {
          '.rgx' => qr/\Gsleep[\ \t]*:[\ \t]*\r?\n/
        },
        {
          '.ref' => 'assignments'
        }
      ]
    },
    'split' => {
      '.all' => [
        {
          '.rgx' => qr/\Gsplit/
        },
        {
          '.ref' => 'colon'
        },
        {
          '.ref' => 'block_indent'
        },
        {
          '+min' => 1,
          '.ref' => 'callflow'
        },
        {
          '.ref' => 'block_undent'
        }
      ]
    },
    'statement' => {
      '.any' => [
        {
          '-wrap' => 1,
          '.ref' => 'call'
        },
        {
          '-wrap' => 1,
          '.ref' => 'case'
        },
        {
          '-wrap' => 1,
          '.ref' => 'eval'
        },
        {
          '-wrap' => 1,
          '.ref' => 'goto'
        },
        {
          '-wrap' => 1,
          '.ref' => 'if'
        },
        {
          '-wrap' => 1,
          '.ref' => 'label'
        },
        {
          '-wrap' => 1,
          '.ref' => 'lock'
        },
        {
          '-wrap' => 1,
          '.ref' => 'raise_error'
        },
        {
          '-wrap' => 1,
          '.ref' => 'raise_event'
        },
        {
          '-wrap' => 1,
          '.ref' => 'repeat'
        },
        {
          '-wrap' => 1,
          '.ref' => 'return'
        },
        {
          '-wrap' => 1,
          '.ref' => 'sleep'
        },
        {
          '-wrap' => 1,
          '.ref' => 'split'
        },
        {
          '-wrap' => 1,
          '.ref' => 'subscribe'
        },
        {
          '-wrap' => 1,
          '.ref' => 'try'
        },
        {
          '-wrap' => 1,
          '.ref' => 'unlock'
        },
        {
          '-wrap' => 1,
          '.ref' => 'unsubscribe'
        },
        {
          '-wrap' => 1,
          '.ref' => 'wait_for_event'
        },
        {
          '-wrap' => 1,
          '.ref' => 'while'
        }
      ]
    },
    'string' => {
      '.any' => [
        {
          '.ref' => 'single_quoted_string'
        },
        {
          '.ref' => 'double_quoted_string'
        }
      ]
    },
    'subscribe' => {
      '.all' => [
        {
          '.rgx' => qr/\Gsubscribe[\ \t]*:[\ \t]*\r?\n/
        },
        {
          '.ref' => 'assignments'
        }
      ]
    },
    'term' => {
      '.any' => [
        {
          '-wrap' => 1,
          '.ref' => 'unop_term'
        },
        {
          '.ref' => 'plain_term'
        }
      ]
    },
    'then' => {
      '.ref' => 'block'
    },
    'try' => {
      '.all' => [
        {
          '.rgx' => qr/\Gtry/
        },
        {
          '.ref' => 'colon'
        },
        {
          '-wrap' => 1,
          '.ref' => 'try_block'
        },
        {
          '.ref' => 'block_ondent'
        },
        {
          '.rgx' => qr/\Gcatch/
        },
        {
          '.ref' => 'colon'
        },
        {
          '-wrap' => 1,
          '.ref' => 'catch_block'
        }
      ]
    },
    'try_block' => {
      '.ref' => 'block'
    },
    'unary_operator' => {
      '.rgx' => qr/\G(!|\-|\+|not\ )/
    },
    'unlock' => {
      '.all' => [
        {
          '.rgx' => qr/\Gunlock[\ \t]+/
        },
        {
          '.ref' => 'identifier'
        },
        {
          '.ref' => '__'
        },
        {
          '.any' => [
            {
              '.ref' => 'perl_block'
            },
            {
              '.ref' => 'rhs'
            }
          ]
        }
      ]
    },
    'unop_term' => {
      '.all' => [
        {
          '.ref' => 'unary_operator'
        },
        {
          '.ref' => 'plain_term'
        }
      ]
    },
    'unsubscribe' => {
      '.all' => [
        {
          '.rgx' => qr/\Gunsubscribe[\ \t]*:[\ \t]*\r?\n/
        },
        {
          '.ref' => 'assignments'
        }
      ]
    },
    'variable' => {
      '.all' => [
        {
          '.rgx' => qr/\G([a-zA-Z])\./
        },
        {
          '.ref' => 'varpart'
        },
        {
          '+min' => 0,
          '.all' => [
            {
              '.rgx' => qr/\G\./
            },
            {
              '.ref' => 'varpart'
            }
          ]
        }
      ]
    },
    'varpart' => {
      '.all' => [
        {
          '.ref' => 'identifier'
        },
        {
          '+max' => 1,
          '.rgx' => qr/\G\[(\-?[0-9]+)\[/
        }
      ]
    },
    'wait_for_event' => {
      '.all' => [
        {
          '.rgx' => qr/\Gwait_for_event/
        },
        {
          '.ref' => 'colon'
        },
        {
          '.ref' => 'call_body'
        }
      ]
    },
    'wfenv' => {
      '.all' => [
        {
          '.rgx' => qr/\Gwfenv[\ \t]*:[\ \t]*\r?\n/
        },
        {
          '.any' => [
            {
              '.ref' => 'assignments'
            },
            {
              '.err' => 'syntax error: wfenv:\\n<assignments>'
            }
          ]
        }
      ]
    },
    'wfomap' => {
      '.all' => [
        {
          '.rgx' => qr/\Gwfomap[\ \t]*:[\ \t]*\r?\n/
        },
        {
          '.any' => [
            {
              '.ref' => 'assignments'
            },
            {
              '.err' => 'syntax error: wfomap:\\n<assignments>'
            }
          ]
        }
      ]
    },
    'when' => {
      '.all' => [
        {
          '.ref' => 'block_ondent'
        },
        {
          '.rgx' => qr/\Gwhen[\ \t]+/
        },
        {
          '-wrap' => 1,
          '.ref' => 'case_label'
        },
        {
          '.ref' => 'colon'
        },
        {
          '-wrap' => 1,
          '.ref' => 'block'
        }
      ]
    },
    'while' => {
      '.all' => [
        {
          '.rgx' => qr/\Gwhile[\ \t]+/
        },
        {
          '-wrap' => 1,
          '.ref' => 'condition'
        },
        {
          '.ref' => 'colon'
        },
        {
          '-wrap' => 1,
          '.ref' => 'block'
        }
      ]
    },
    'workflow' => {
      '.all' => [
        {
          '.rgx' => qr/\Gworkflow[\ \t]+/
        },
        {
          '-wrap' => 1,
          '.ref' => 'workflow_name'
        },
        {
          '.ref' => 'colon'
        },
        {
          '.any' => [
            {
              '+min' => 1,
              '.any' => [
                {
                  '-skip' => 1,
                  '.ref' => 'ignorable'
                },
                {
                  '-wrap' => 1,
                  '.ref' => 'in'
                },
                {
                  '-wrap' => 1,
                  '.ref' => 'out'
                },
                {
                  '-wrap' => 1,
                  '.ref' => 'wfenv'
                },
                {
                  '-wrap' => 1,
                  '.ref' => 'role'
                },
                {
                  '-wrap' => 1,
                  '.ref' => 'config'
                },
                {
                  '-wrap' => 1,
                  '.ref' => 'locks'
                },
                {
                  '-wrap' => 1,
                  '.ref' => 'wfomap'
                },
                {
                  '-wrap' => 1,
                  '.ref' => 'do'
                }
              ]
            },
            {
              '.err' => 'syntax error: workflow [name]\\n:<workflow>'
            }
          ]
        }
      ]
    },
    'workflow_name' => {
      '.ref' => 'identifier'
    }
  }
}

sub foo {
	say 'foo!';
}

1;
