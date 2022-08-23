package App::pickaxe::DisplayMsg;
use Mojo::Base -signatures, 'Exporter';
use Curses;

our @EXPORT_OK = 'display_msg';

sub display_msg ($msg) {
    move( $LINES - 1, 0 );
    clrtoeol;
    $msg = substr($msg, 0, $COLS);
    addstring($msg);
    refresh;
}

1;
