package App::pickaxe::Getline;
use Mojo::Base -signatures, 'Exporter';
use App::pickaxe::Keys 'getkey';
use Curses;

our @EXPORT_OK = qw(getline);

my %getline_bindings = (
    '<Backspace>'     => 'backward_delete_character',
    '<Left>'          => 'backward_char',
    '<Right>'         => 'forward_char',
    '<Up>'            => 'prev_history',
    '<Down>'          => 'next_history',
    '^P'              => 'prev_history',
    '^N'              => 'next_history',
    '^A'              => 'beginning_of_line',
    '^E'              => 'end_of_line',
    '^D'              => 'delete_character',
    '^K'              => 'kill_line',
    '^G'              => 'abort',
    '<Return>'        => 'accept_line',
    '<Esc>d'           => 'kill_word',
    '<Esc><Backspace>' => 'backward_kill_word',
    '<Esc>\\'          => 'delete_horizontal_space',
);

my $buffer = '';
my $cursor = 0;
my @history;
my $history_index;

sub getline ( $prompt, $options = {} ) {
    my ( $lines, $cols );
    move( $LINES - 1, 0 );
    $buffer = $options->{buffer} || '';
    $cursor = length($buffer);

    $history_index = 0;
    @history       = @{ $options->{history} || [] };
    unshift @history, $buffer;

    clrtoeol;
    addstring($prompt);
    addstring($buffer);
    chgat( $LINES - 1, $cursor + length($prompt), 1, A_REVERSE, 0, 0 );
    refresh;
    while (1) {
        my $key = getkey;

        my $funcname = $getline_bindings{$key} || 'self_insert';
        if ( $funcname eq 'accept_line' ) {
            last;
        }
        if ( $funcname eq 'abort' ) {
            $buffer = '';
            last;
        }
        no strict 'refs';
        &$funcname( $key, $options );

        move( $LINES - 1, length($prompt) );
        clrtoeol;
        my $rlcols = $COLS - length($prompt) - 1; # -1 extra space for indicator

        my $offset = int( $cursor / $rlcols ) * $rlcols;
        my $x      = substr( $buffer, $offset, $rlcols );

        if ( $options->{password} ) {
            $x = '*' x length($x);
        }
        addstring($x);
        if ( $offset != 0 ) {
            addstring( 0, $COLS - 1, '<' );
        }
        elsif ( length($buffer) > $rlcols ) {
            addstring( 0, $COLS - 1, '>' );
        }
        chgat( $LINES - 1, $cursor + length($prompt) - $offset,
            1, A_REVERSE, 0, 0 );

        refresh;
    }
    move( $LINES - 1, 0 );
    clrtoeol;
    my $subwin = subwin( $stdscr, 1, $COLS, $LINES - 1, 0 );
    refresh($subwin);

    if ( $buffer && $options->{history} ) {
        unshift @{ $options->{history} }, $buffer;
    }

    return $buffer;
}

sub delete_character {
    substr( $buffer, $cursor, 1, '' );
}

sub backward_delete_character {
    if ($cursor) {
        substr( $buffer, $cursor - 1, 1, '' );
        $cursor--;
    }
}

sub self_insert ( $key, $options ) {
    if ( $key eq '<Space>' ) {
        $key = ' ';
    }
    substr( $buffer, $cursor, 0, $key );
    $cursor++;
}

sub backward_char {
    $cursor-- if $cursor;
}

sub forward_char {
    $cursor++ if $cursor != length($buffer);
}

sub beginning_of_line {
    $cursor = 0;
}

sub end_of_line {
    $cursor = length($buffer);
}

sub kill_line {
    substr( $buffer, $cursor ) = '';
}

sub next_history {
    $history[$history_index] = $buffer;
    $history_index = $history_index - 1 < 0 ? @history - 1 : $history_index - 1;
    $buffer        = $history[$history_index];
    $cursor        = length($buffer);
}

sub prev_history {
    $history[$history_index] = $buffer;
    $history_index = $history_index + 1 >= @history ? 0 : $history_index + 1;
    $buffer        = $history[$history_index];
    $cursor        = length($buffer);
}

sub kill_word {
    substr( $buffer, $cursor ) =~ s/\s*\S+//;
}

sub backward_kill_word {
    substr( $buffer, 0, $cursor ) =~ s/\S+\s*$//;
    $cursor = length($buffer);
}

sub delete_horizontal_space {
    substr( $buffer, $cursor ) =~ s/^\s+//;
    substr( $buffer, 0, $cursor ) =~ s/(\s+)$//;
    if ($1) {
        $cursor -= length($1);
    }
}

1;
