package App::pickaxe::DisplayMsg;
use Mojo::Base -signatures, 'Exporter';
use Curses;

our @EXPORT_OK = 'display_msg';

sub display_msg ($msg) {
    move( $LINES - 1, 0 );
    clrtoeol;
    addstring($msg);
    refresh;
}

1;
