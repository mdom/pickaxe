package App::pickaxe::SelectOption;
use Mojo::Base -signatures, 'Exporter';
use App::pickaxe::Keys 'getkey';
use Curses;

our @EXPORT_OK = ( 'select_option', 'askyesno' );

sub askyesno ($question) {
    my $ret = select_option( $question, qw(Yes No));
    if ( !defined $ret or $ret eq 'no' ) {
        return 0;
    }
    else {
        return 1;
    }
}

sub clear_last_line {
    move( $LINES - 1, 0 );
    clrtoeol;
}

sub select_option ( $prompt, @options ) {
    clear_last_line;
    addstring("$prompt " . join('/', @options) . '?: ');
    my %options = map { /([A-Z])/; lc($1) => lc($_) } @options;
    while (1) {
        my $key = getkey;
        if ( $key eq "^G" ) {
            clear_last_line;
            return;
        }
        elsif ( exists $options{$key} ) {
            clear_last_line;
            return $options{$key};
        }
    }
}

1;
