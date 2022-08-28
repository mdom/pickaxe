package App::pickaxe::Config;
use Mojo::Base -signatures, -base;
use Mojo::Util 'decode';
use Mojo::File 'path';
use Text::ParseWords 'shellwords';
use Mojo::URL;
use Curses;

has 'username';
has 'password';

has filter_cmd  => sub { [qw(pandoc -f textile -t plain)] };
has filter_mode => 'no';
has pass_cmd    => sub { [] };
has maps        => sub { {} };

sub base_url ( $self, $url = undef ) {
    if ($url) {
        $self->{base_url} = Mojo::URL->new($url);
    }
    return $self->{base_url};
}

sub new ($class) {
    my $file = ( $ENV{XDG_CONFIG_HOME} || "$ENV{HOME}/.config" )
      . "/pickaxe/pickaxe.conf";
    if ( !-e $file ) {
        return {};
    }
    my $path   = path($file);
    my $handle = $path->open('<:encoding(UTF-8)');
    my $has_errors;
    my $config = bless {}, ref $class || $class;
    my $last_line;
    while (<$handle>) {
        chomp;
        s/#.*$//;
        next if /^\s*$/;

        ## handle line continuations with \
        if ($last_line) {
            $_         = $last_line . $_;
            $last_line = undef;
        }
        if (s/\\\s*$//) {
            $last_line = $_;
            next;
        }

        my ( $cmd, @args ) = shellwords($_);
        if ( $cmd eq 'set' ) {
            my ( $key, $value, @rest ) = @args;
            if ( !$config->can($key) ) {
                warn "Error in $file, line $.: $key: unknown variable\n";
                $has_errors++;
            }
            elsif ( ref($config->$key) eq 'ARRAY' ) {
                $config->$key( [ $value, @rest ] );
            }
            else {
                $config->$key($value);
            }
        }
        elsif ( $cmd eq 'bind' ) {
            my ( $map, $key, $function ) = @args;
            $config->maps->{$map}->{$key} = $function;
        }
        else {
            warn "Error in $file, line $.: $cmd: unknown command\n";
            $has_errors++;
        }
    }
    if ($has_errors) {
        say "Press any key to continue...";
        <STDIN>;
    }
    return $config;
}

1;
