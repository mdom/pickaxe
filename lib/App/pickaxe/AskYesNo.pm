package App::pickaxe::AskYesNo;
use Mojo::Base -signatures, 'Exporter';
use Curses;

our @EXPORT_OK = 'askyesno';

sub askyesno ( $win, $question ) {
    move( $win, 0, 0 );
    clrtoeol($win);
    addstring( $win, $question . " ([yes]/no): " );
    while (1) {
        my $key = getchar;
        if ( $key eq 'y' or $key eq 'n' or $key eq "\n" ) {
            move( $win, 0, 0 );
            clrtoeol($win);
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
