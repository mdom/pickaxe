package App::pickaxe::SelectOption;
use Mojo::Base -signatures, 'Exporter';
use Curses;

our @EXPORT_OK = ( 'select_option', 'askyesno' );

sub askyesno ($question) {
    select_option( $question, qw(Yes No)) eq 'yes' ? 1 : 0;
}

sub select_option ( $prompt, @options ) {
    move( $LINES - 1, 0 );
    clrtoeol;
    addstring("$prompt " . join('/', @options) . '?: ');
    my %options = map { /([A-Z])/; lc($1) => lc($_) } @options;
    while (1) {
        my $key = getchar;
        if ( exists $options{$key} ) {
            move( $LINES - 1, 0 );
            clrtoeol;
            return $options{$key};
        }
    }
}

1;
