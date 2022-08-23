package App::pickaxe::SelectOption;
use Mojo::Base -signatures, 'Exporter';
use Curses;

our @EXPORT_OK = ('select_option', 'askyesno');

sub askyesno ( $question ) {
    select_option("$question ([yes]/no): ", { y => 1, n => 0, "\n" => 1 });
}

sub select_option ( $prompt, $options ) {
    move( $LINES - 1, 0 );
    clrtoeol;
    addstring($prompt);
    while (1) {
        my $key = getchar;
        if ( exists $options->{$key} ) {
            move( $LINES - 1, 0 );
            clrtoeol;
            return $options->{$key};
        }
    }
}

1;
