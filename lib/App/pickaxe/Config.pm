package App::pickaxe::Config;
use Mojo::Base -signatures, 'Exporter';
use Mojo::Util 'decode';
use Mojo::File 'path';

our @EXPORT_OK = 'read_config';

sub read_config {
    my $file = ( $ENV{XDG_CONFIG_HOME} || "$ENV{HOME}/.config" )
      . "/pickaxe/pickaxe.conf";
    if ( !-e $file ) {
        return {};
    }
    my $content = decode( 'UTF-8', path($file)->slurp );
    my $config =
      eval "package Sandbox; no warnings;use Mojo::Base -strict; $content";

    die qq{Can't load configuration from file "$file" : $@;} if $@;
    die qq{Configuration file "$file" did not return a hash reference}
      unless ref $config eq 'HASH';

    return $config;
}
