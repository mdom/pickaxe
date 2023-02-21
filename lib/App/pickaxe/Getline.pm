package App::pickaxe::Getline;
use Mojo::Base -signatures, 'Exporter';

use App::pickaxe::Keys 'getkey';
use Curses;
use Mojo::File 'path';

our @EXPORT_OK = qw(getline);

my %getline_bindings = (
    '<Backspace>'      => 'backward_delete_character',
    '<Left>'           => 'backward_char',
    '<Right>'          => 'forward_char',
    '<Up>'             => 'prev_history',
    '<Down>'           => 'next_history',
    '^P'               => 'prev_history',
    '^N'               => 'next_history',
    '^A'               => 'beginning_of_line',
    '^E'               => 'end_of_line',
    '^D'               => 'delete_character',
    '^K'               => 'kill_line',
    '^G'               => 'abort',
    '<Return>'         => 'accept_line',
    '<Esc>d'           => 'kill_word',
    '<Esc><Backspace>' => 'backward_kill_word',
    '<Esc><Backslash>' => 'delete_horizontal_space',
    '<Tab>'            => 'complete',
);

my $buffer = '';
my $cursor = 0;
my @history;
my $history_index;
my $prev_key = '';
my @current_completions;

sub getline ( $prompt, $options = {} ) {
    my ( $lines, $cols );
    move( $LINES - 1, 0 );
    $buffer = $options->{buffer} || '';
    $cursor = length($buffer);

    $history_index = 0;
    @current_completions = ();
    @history       = @{ $options->{history} || [] };
    unshift @history, $buffer;

    clrtoeol;
    addstring($prompt);
    addstring($buffer);
    chgat( $LINES - 1, $cursor + length($prompt), 1, A_REVERSE, 0, 0 );
    refresh;
    while (1) {
        my $key = getkey;
        next if ! defined $key;

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

        ## $prev_key is used in complete() to determine if the last
        ## pressed key was a tab.
        $prev_key = $key;

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
    $cursor += length($key);
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

sub cycle_shift ($array) {
    my $elt = shift @$array;
    push @$array, $elt;
    return $elt;
}

sub generate_filecompletions ($path) {
    $path = path($path||'.');
    my @completions;
    if ( -d $path ) {
        @completions = $path->list( { dir => 1 } )->map('to_rel')->each;
    }
    else {
        my $dir  = $path->dirname;
        my $name = $path->basename;
        for my $file ( $dir->list( { dir => 1 } )->each ) {
            if ( index( $file->basename, $name ) == 0 ) {
                push @completions, $file->to_rel;
            }
        }
    }
    return @completions;
}

sub complete ( $key, $options ) {
    my $completion_matches = $options->{completion_matches} || \&generate_filecompletions;
    if ( $prev_key ne '<Tab>' || !@current_completions ) {
        @current_completions = ();
        substr( $buffer, 0, $cursor ) =~ /(\S+)$/;
        @current_completions = sort +$completion_matches->($1);

    }
    if (@current_completions) {
        substr( $buffer, 0, $cursor ) =~ s/(\S+)$//;
        $cursor -= length($1)||0;

        my $elt = cycle_shift( \@current_completions );
        substr( $buffer, $cursor, 0, $elt );
        $cursor += length($elt);
    }
    if ( @current_completions == 1 ) {
        @current_completions = ();
    }
    return;
}

1;
