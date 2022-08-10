package App::pickaxe::AskYesNo;
use Mojo::Base -signatures, 'Exporter';
use Curses;

our @EXPORT_OK = 'askyesno';

sub askyesno ( $question ) {
    move( $LINES - 1, 0 );
    clrtoeol;
    addstring( $question . " ([yes]/no): " );
    while (1) {
        my $key = getchar;
        if ( $key eq 'y' or $key eq 'n' or $key eq "\n" ) {
            move( $LINES - 1, 0 );
            clrtoeol;
            if ( $key eq 'y' or $key eq "\n" ) {
                return 1;
            }
            elsif ( $key eq 'n' ) {
                return 0;
            }
        }
    }
}

1;
