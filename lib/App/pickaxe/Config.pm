package App::pickaxe::Config;
use Mojo::Base -signatures, 'Exporter';
use Mojo::Util 'decode';
use Mojo::File 'path';
use Text::ParseWords 'shellwords';
use Curses;

our @EXPORT_OK = 'read_config';

my %defaults = (
   url => '',
   bind => '',
   filter_cmd => [qw(pandoc -f textile -t plain)],
   filter_mode => 'no',
   username => '',
   password => '',
   pass_cmd => [],
);

sub read_config {
    my $file = ( $ENV{XDG_CONFIG_HOME} || "$ENV{HOME}/.config" )
      . "/pickaxe/pickaxe.conf";
    if ( !-e $file ) {
        return {};
    }
    my $path = path($file);
    my $handle = $path->open('<:encoding(UTF-8)');
    my $has_errors;
    my $config = {%defaults};
    my $last_line;
    while (<$handle>) {
        chomp;
        s/#.*$//;
        next if /^\s*$/;

        ## handle line continuations with \ 
        if ( $last_line ) {
            $_ = $last_line . $_;
            $last_line = undef;
        }
        if ( s/\\\s*$// ) {
           $last_line = $_;
           next;
        }

        my ($cmd, @args ) = shellwords($_);
        if ( $cmd eq 'set' ) {
            my ($key, $value, @rest) = @args;
            if ($key eq 'filter_cmd' ) {
                $config->{$key} = [ $value, @rest ];
            }
            elsif ($key eq 'pass_cmd' ) {
                $config->{$key} = [ $value, @rest ];
            }
            else {
                $config->{$key} = $value;
            }
        }
        elsif ( $cmd eq 'bind' ) {
            my ($map, $key, $function ) = @args;
            $config->{maps}->{$map}->{$key} = $function;
        }
        else {
            warn "Error in $file, line $.: $cmd: unknown command\n";
            $has_errors++;
        }
    }
    if ( $has_errors ) {
        say "Press any key to continue...";
        <STDIN>;
    }
    return $config;
}
__END__

url "http://taz.de"
project abt_edv_wiki
pass_cmd "pass mdom@taz.de"

bind editor ^C foo_bar
