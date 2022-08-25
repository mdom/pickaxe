package App::pickaxe::Config;
use Mojo::Base -signatures, 'Exporter';
use Mojo::Util 'decode';
use Mojo::File 'path';
use Text::ParseWords 'shellwords';
use Curses;

our @EXPORT_OK = 'read_config';

sub read_config {
    my $file = ( $ENV{XDG_CONFIG_HOME} || "$ENV{HOME}/.config" )
      . "/pickaxe/pickaxe.conf";
    if ( !-e $file ) {
        return {};
    }
    my $path = path($file);
    my $handle = $path->open('<:encoding(UTF-8)');
    my $has_errors;
    my $config = {};
    while (<$handle>) {
        chomp;
        s/#.*$//;
        my ($cmd, @args ) = shellwords($_);
        if ( $cmd eq 'set' ) {
            my ($key, $value) = @args;
            $config->{$args[0]} = $args[1];
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

set url "http://taz.de"
set project abt_edv_wiki
bind editor ^C foo_bar
set pass_cmd "pass mdom@taz.de"
