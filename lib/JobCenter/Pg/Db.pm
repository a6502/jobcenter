package JobCenter::Pg::Db;
use Mojo::Base 'Mojo::Pg::Database';

# override DESTROY so that we call our own _jcpg_enqueue

sub DESTROY {
  my $self = shift;

  #say "destroying $self";

  my $waiting = $self->{waiting};
  $waiting->{cb}($self, 'Premature connection close', undef) if $waiting->{cb};

  return unless (my $pg = $self->pg) && (my $dbh = $self->dbh);
  # we need to always call _jcpg_enqueue to update the connection count
  $pg->__jcpg_enqueue($dbh); # unless $dbh->{private_mojo_no_reuse};
}


1;

