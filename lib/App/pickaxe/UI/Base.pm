package App::pickaxe::UI::Base;
use Mojo::Base 'Mojo::EventEmitter', -signatures;
use Curses;
use App::pickaxe::Keys 'getkey';
use App::pickaxe::Getline 'getline';
use Mojo::Util 'decamelize';

has 'lines'   => sub { [] };
has 'message' => '';
has 'matches';

has nlines         => 0;
has ncolumns       => 0;
has current_line   => 0;
has current_column => 0;

has find_active => 0;

has moniker => sub ($self) {
    my $map = ref($self);
    $map =~ s/.*:://;
    return lc( decamelize($map) );
};

has statusbar => '';
has helpbar   => '';

sub maxlines { $LINES - 3 }

sub first_line_on_page ($self) {
    return $self->current_line;
}

sub set_lines ( $self, @lines ) {
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
    my $help = substr( $self->helpbar || '', 0, $COLS );
    attron(A_REVERSE);
    addstring( 0, 0, ' ' x $COLS );
    addstring( 0, 0, $self->helpbar );
    attroff(A_REVERSE);
}

sub update_statusbar ($self) {
    my ( $left, $right ) = $self->statusbar;
    $left  = substr( $left  || '', 0, $COLS );
    $right = substr( $right || '', 0, $COLS - 1 );
    attron(A_REVERSE);
    addstring( $LINES - 2, 0,                         ' ' x $COLS );
    addstring( $LINES - 2, 0,                         $left );
    addstring( $LINES - 2, $COLS - length(" $right"), " $right" );
    attroff(A_REVERSE);
}

sub render ($self) {
    erase;
    $self->update_statusbar;
    $self->update_helpbar;

    $self->display_msg( $self->message );

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
    } while ( $current->[0] == $self->current_line && $current != $start );

    $self->find_goto_line( $self->matches->[0]->[0], $direction );

    return;
}

sub find_goto_line ( $self, $line, $direction ) {
    if ( $line < $self->current_line && $direction == 1 ) {
        $self->message('Search wrapped to top.');
    }
    elsif ( $line > $self->current_line && $direction == -1 ) {
        $self->message('Search wrapped to bottom.');
    }

    $self->goto_line($line);
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

sub find ( $self, $key, $direction = 1 ) {
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
        $self->find_goto_line( $self->matches->[0]->[0], $direction );
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
    $self->emit('change_line');
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

sub display_msg ( $self, $msg ) {
    move( $LINES - 1, 0 );
    clrtoeol;
    $msg = substr( $msg, 0, $COLS );
    addstring($msg);
}

sub display_help ( $self, $key ) {
    my $keybindings = $self->current_keybindings;
    my @lines;
    for my $key ( sort keys %$keybindings ) {
        push @lines, sprintf( "%-10s %s", $key, $keybindings->{$key} );
    }
    App::pickaxe::UI::Pager->new->helpbar("q:Quit")
      ->statusbar( "Help for " . $self->moniker )->set_lines(@lines)->run;
}

has current_keybindings => sub { {} };

has exit_after_call => 0;

sub run ( $self, $keybindings = {} ) {
    $self->current_keybindings(
        {
            %{ $self->keybindings }, %{ $keybindings->{ $self->moniker } || {} }
        }
    );

    $self->render;
    while (1) {
        my $key = getkey;
        next if !$key;
        if ( $key eq '<Resize>' ) {
            $self->render;
            next;
        }
        $self->message('');

        my $funcname = $self->current_keybindings->{$key};

        if ( !$funcname ) {
            $self->message('Key is not bound.');
        }
        elsif ( $funcname eq 'quit' ) {
            last;
        }
        else {
            $self->$funcname($key);
            if ( $self->exit_after_call ) {
                $self->exit_after_call(0);
                last;
            }
        }
        $self->render;
        refresh;
    }
}

sub empty ($self) {
    return !@{ $self->lines };
}

sub jump ( $self, $key ) {
    return if $self->empty;
    my $number = getline( "Jump to line: ", { buffer => $key } );
    if ( !$number || $number =~ /\D/ ) {
        $self->display_msg("Argument must be a number.");
        return;
    }
    $self->goto_line( $number - 1 );
}

sub force_render ( $self, @ ) {
    clearok( stdscr, 1 );
    $self->render;
}

1;
