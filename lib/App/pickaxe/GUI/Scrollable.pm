package App::pickaxe::GUI::Scrollable;
use Mojo::Base -base, -signatures;
use Curses;
use App::pickaxe::Keys 'getkey';
use App::pickaxe::Getline 'getline';
use Mojo::Util 'decamelize';

has 'lines' => sub { [] };
has 'message' => '';
has 'matches';

has nlines         => 0;
has ncolumns       => 0;
has current_line   => 0;
has current_column => 0;

has find_active => 0;

has maxlines => sub { $LINES - 3 };

has moniker => sub ($self) {
    my $map = lc(ref($self));
    $map =~ s/.*:://;
    decamelize($map)
};

sub statusbar ($self) {
    return ('', '' );
}

sub helpbar ($self) {
    return '';
}

sub first_line_on_page ($self) {
    return $self->current_line;
}

sub set_lines ($self, @lines) {
    $self->nlines( @lines + 0 );
    $self->lines( \@lines );
    $self->current_line(0);
    $self->current_column(0);
    $self->matches( [] );

    my $cols = 0;
    for my $line (@lines) {
        if ( length($line) > $cols ) {
            $cols = length($line);
        }
    }
    $self->ncolumns($cols);
}

sub update_helpbar ($self) {
    move( 0, 0 );
    clrtoeol;
    attron(A_REVERSE);
    my $help = $self->helpbar;
    $help = substr( $help, 0, $COLS - 1 );
    addstring( $help . ( ' ' x ( $COLS - length($help) ) ) );
    attroff(A_REVERSE);
}

sub update_statusbar ($self) {
    move( $LINES - 2, 0 );
    clrtoeol;
    attron(A_REVERSE);
    my ( $left, $right ) = $self->statusbar;
    $right //= '';
    $left  //= '';
    $left  = substr( $left,  0, $COLS - 1 );
    $right = substr( $right, 0, $COLS - 1 );
    addstring( $left . ( ' ' x ( $COLS - length($left) ) ) );
    addstring( $LINES - 2, $COLS - 1 - length($right), $right );
    attroff(A_REVERSE);
}

sub render ( $self, @ ) {

    erase;
    $self->update_statusbar;
    $self->update_helpbar;

    display_msg( $self->message );

    my $first_line = $self->first_line_on_page;
    my $last_line  = $first_line + $self->maxlines - 1;

    if ( $last_line > $self->nlines - 1 ) {
        $last_line = $self->nlines - 1;
    }

    my $x = 0;
    for my $line ( @{ $self->lines }[ $first_line .. $last_line ] ) {
        my $substr;
        if ( $self->current_column <= length($line) ) {
            $substr = substr( $line, $self->current_column,
                $self->current_column + $COLS );
        }
        else {
            $substr = '';
        }
        addstring( $x + 1, 0, $substr );
        $x++;
    }

}

## $direction == 1 is forward_search and $directon == -1 is reverse
sub find_next ( $self, $key, $direction = 1 ) {

    if ( !@{ $self->matches } ) {
        $self->find( $key, $direction );
        return;
    }

    ## find_active is always active with a new search. When we have
    ## matches and find_active is disabled, the user has called find_toggle
    ## before. So we have to toggle it back here.

    if ( @{ $self->matches } && !$self->find_active ) {
        $self->find_active(1);
    }

    my $shifter = $direction == -1 ? \&cycle_shift_reverse : \&cycle_shift;

    ## TODO this loops endlessly if all matches are on the same line
    ##      should traverse matches only once
    ##      add extra array with just the line numbers
    my $start = $self->matches->[0];
    my $current;
    do {
        $current = $shifter->( $self->matches );
    }
    while ( $current->[0] == $self->current_line && $current != $start );

    $self->find_goto_line( $self->matches->[0]->[0] );

    return;
}

sub find_goto_line ( $self, $line ) {
    if ( $line < $self->current_line ) {
        $self->message('Search wrapped to top.');
    }

    $self->goto_line( $line );
}

sub find_next_reverse ( $self, $key ) {
    $self->find_next( $key, -1 );
}

sub cycle_shift ($array) {
    my $elt = shift @$array;
    push @$array, $elt;
    return $elt;
}

sub cycle_shift_reverse ($array) {
    my $elt = pop @$array;
    unshift @$array, $elt;
    return $elt;
}

sub find ( $self, $key, $direction = 0 ) {
    my $prompt = 'Find string' . ( $direction == -1 ? ' reverse' : '' );
    state $history = [];
    my $needle = getline( "$prompt: ", { history => $history } );
    return if !$needle;

    my @lines = @{ $self->lines };
    my $pos   = $self->current_line;

    my @matches;
    my $len = length($needle);
    for my $line_no ( $pos .. @lines - 1, 0 .. $pos - 1 ) {
        my $line = $lines[$line_no];
        while ( $line =~ /\Q$needle\E/gi ) {
            push @matches, [ $line_no, $-[0], $len ];
        }
    }
    if (@matches) {
        $self->matches( \@matches );
        $self->find_active(1);
        $self->find_goto_line( $self->matches->[0]->[0] );
    }
    else {
        $self->matches( [] );
        $self->find_active(0);
        $self->message("Not found.");
    }
    return;
}

sub find_reverse ( $self, $key ) {
    $self->find( $key, -1 );
}

sub scroll_left ( $self, $key ) {
    $self->set_column( $self->current_column - $COLS / 2 );
}

sub scroll_right ( $self, $key ) {
    $self->set_column( $self->current_column + $COLS / 2 );
}

sub set_column ( $self, $new ) {
    $self->current_column($new);
    if ( $self->current_column < 0 ) {
        $self->current_column(0);
    }
    elsif ( $self->current_column > $self->ncolumns - $COLS / 2 ) {
        $self->current_column( $self->ncolumns - $COLS / 2 );
    }
}

sub goto_line ( $self, $new ) {
    $self->current_line($new);
    if ( $self->current_line < 0 ) {
        $self->current_line(0);
    }
    elsif ( $self->current_line > $self->nlines - 1 ) {
        $self->current_line( $self->nlines - 1 );
    }
}

sub next_line ( $self, $key ) {
    $self->goto_line( $self->current_line + 1 );
}

sub prev_line ( $self, $key ) {
    $self->goto_line( $self->current_line - 1 );
}

sub next_screen ( $self, $key ) {
    $self->goto_line( $self->current_line + $self->maxlines );
}

sub prev_page ( $self, $key ) {
    $self->goto_line( $self->current_line - $self->maxlines );
}

sub top ( $self, $key ) {
    $self->goto_line(0);
}

sub bottom ( $self, $key ) {
    $self->goto_line( $self->nlines - $self->maxlines );
}

sub display_msg ($msg) {
    move( $LINES - 1, 0 );
    clrtoeol;
    $msg = substr($msg, 0, $COLS);
    addstring($msg);
}

sub run ($self, $keybindings) {
    $self->render;
    while (1) {
        my $key = getkey;
        next if !$key;
        $self->message('');

        my $funcname = $keybindings->{$self->moniker}->{$key};

        if ( !$funcname ) {
            $self->message('Key is not bound.');
        }
        elsif ( $funcname eq 'quit' ) {
            last;
        }
        else {
            $self->$funcname($key);
        }
        $self->render;
        refresh;
    }
}

sub jump ( $self, $key ) {
    return if $self->pages->empty;
    my $number = getline( "Jump to line: ", { buffer => $key } );
    if ( !$number || $number =~ /\D/ ) {
        display_msg("Argument must be a number.");
        return;
    }
    $self->goto_line( $number - 1 );
}


sub force_render ( $self, @ ) {
    clearok( stdscr, 1 );
    $self->render;
}

1;
