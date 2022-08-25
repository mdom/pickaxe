package App::pickaxe::Pager;
use Mojo::Base -signatures, 'App::pickaxe::Controller';
use Curses;
use App::pickaxe::DisplayMsg 'display_msg';
use App::pickaxe::Getline 'getline';
use IPC::Cmd 'run_forked';
use Mojo::Util 'decode', 'encode';

my $CLEAR = 1;

has help_summary => "q:Quit e:Edit /:find o:Open %:Preview ?:help";

has bindings => sub {
    return {
        'q'                   => 'quit',
        'e'                   => 'edit_page',
        'w'                   => 'create_page',
        Curses::KEY_NPAGE     => 'next_page',
        " "                   => 'next_page',
        Curses::KEY_PPAGE     => 'prev_page',
        Curses::KEY_DOWN      => 'next_line',
        "\n"                  => 'next_line',
        Curses::KEY_UP        => 'prev_line',
        Curses::KEY_BACKSPACE => 'prev_line',
        '%'                   => 'toggle_filter_mode',
        Curses::KEY_HOME      => 'top',
        Curses::KEY_END       => 'bottom',
        Curses::KEY_LEFT      => 'scroll_left',
        Curses::KEY_RIGHT     => 'scroll_right',
        '/'                   => 'find',
        'n'                   => 'find_next',
        '\\'                  => 'find_toggle',
        o                     => 'open_in_browser',
    };
};

has 'index';

has filter_mode => 0;

sub which ($cmd) {
    for my $path ( split( ':', $ENV{PATH} ) ) {
        if ( -e "$path/$cmd" ) {
            return "$path/$cmd";
        }
    }
    return '';
}

has filter => sub { [ 'pandoc', '-f', 'textile', '-t', 'plain' ] };

has nlines   => 0;
has ncolumns => 0;

has current_line   => 0;
has current_column => 0;

has 'lines';

has 'pad';

has 'needle';
has 'matches';

sub status ($self) {
    my $base  = $self->state->base_url->clone->query( key => undef );
    my $title = $self->state->pages->current->{title};
    my $percent;
    if ( $self->nlines == 0 ) {
        $percent = '100';
    }
    else {
        $percent = int( $self->current_line / $self->nlines * 100 );
    }
    return "pickaxe: $base $title", sprintf( "--%3d%%", $percent );
}

sub edit_page ( $self, $key ) {
    $self->SUPER::edit_page($key);
    $self->create_pad;
    $self->redraw(1);
}

sub create_pad ($self) {
    if ( $self->pad ) {
        $self->pad->delwin;
    }
    my $cols = $COLS;
    my $text = $self->api->text_for( $self->pages->current->{title} );

    if ( $text && $self->filter_mode ) {
        ## in case $self->filter messes with the terminal
        endwin;
        my $result = run_forked( $self->filter,
            { child_stdin => encode( 'utf8', $text ) } );

        if ( $result->{exit_code} == 0 ) {
            $text = decode( 'utf8', $result->{stdout} );
        }
        else {
            display_msg(
                "Can't call " . $self->filter . ": " . $result->{stderr} );
        }
    }

    my @lines = split( "\n", $text );

    $self->nlines( @lines + 0 );
    $self->lines( \@lines );
    $self->current_line(0);
    $self->matches( [] );

    for my $line (@lines) {
        if ( length($line) > $cols ) {
            $cols = length($line);
        }
    }

    $self->ncolumns($cols);

    my $pad = newpad( @lines + 1, $cols );

    my $x = 0;
    for my $line (@lines) {
        addstring( $pad, $x, 0, $line ) or die "addstring: $line\n";
        $x++;
    }
    $self->pad($pad);
}

sub DESTROY ($self) {
    if ( $self->pad ) {
        $self->pad->delwin;
    }
}

sub redraw ( $self, $clear = 0 ) {
    if ($clear) {
        clear;
        refresh;
        $self->SUPER::redraw;
    }
    $self->update_statusbar;
    $self->pad->prefresh( $self->current_line, $self->current_column, 1, 0,
        $self->maxlines, $COLS - 1 );
}

has find_active => 1;

sub find_toggle ( $self, $key ) {
    return if !@{ $self->matches };
    my $style;
    if ( $self->find_active ) {
        $self->find_active(0);
        $style = A_NORMAL;
    }
    else {
        $self->find_active(1);
        $style = A_REVERSE;
    }
    for my $match ( @{ $self->matches } ) {
        chgat( $self->pad, @$match, $style, 0, 0 );
    }
    $self->redraw;
}

has find_history => sub { [] };

sub find_next ( $self, $key ) {
    if ( !$self->needle ) {
        my $needle =
          getline( "Find string: ", { history => $self->find_history } );
        return if !$needle;

        $needle = lc($needle);
        $self->needle($needle);

        my @lines = @{ $self->lines };
        my $pos   = $self->current_line;

        for my $match ( @{ $self->matches } ) {
            chgat( $self->pad, @$match, A_NORMAL, 0, 0 );
        }

        my @matches;
        my $len = length($needle);
        for my $line_no ( $pos .. @lines - 1, 0 .. $pos - 1 ) {
            my $line = $lines[$line_no];
            while ( $line =~ /\Q$needle\E/gi ) {
                push @matches, [ $line_no, $-[0], $len ];
                chgat( $self->pad, $line_no, $-[0], $len, A_REVERSE, 0, 0 );
            }
        }
        $self->find_active(1);
        $self->matches( \@matches );
        $self->redraw;
    }

    ## find_active is always active with a new search. When we have
    ## matches and find_active is disabled, the user has called find_toggle
    ## before. So we have to toggle it back here.

    if ( @{ $self->matches } && !$self->find_active ) {
        $self->find_toggle($key);
    }

    if ( @{ $self->matches } == 1 ) {
        $self->set_line( $self->matches->[0]->[0], 1 );
    }
    elsif ( @{ $self->matches } > 1 ) {
        while (1) {
            my $match = cycle_shift( $self->matches );
            if ( $match->[0] != $self->current_line ) {
                $self->set_line( $match->[0], 1 );
                last;
            }
        }
    }
    else {
        display_msg "Not found.";
    }
    return;
}

sub cycle_shift ($array) {
    my $elt = shift @$array;
    push @$array, $elt;
    return $elt;
}

sub find ( $self, $key ) {
    $self->needle('');
    $self->find_next($key);
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

    $self->redraw(1);
}

sub set_line ( $self, $new, $clear = 0 ) {
    $self->current_line($new);
    if ( $self->current_line < 0 ) {
        $self->current_line(0);
    }
    elsif ( $self->current_line > $self->nlines - 1 ) {
        $self->current_line( $self->nlines - 1 );
    }
    $self->redraw($clear);
}

sub toggle_filter_mode ( $self, $key ) {

    ## Enable filter mode only if filter exists
    if ( !$self->filter_mode ) {
        my $cmd = $self->filter->[0];
        if ( !which($cmd) ) {
            display_msg("$cmd not found.");
            return;
        }
    }

    $self->filter_mode( !$self->filter_mode );
    $self->create_pad;
    $self->redraw(1);
    if ( $self->filter_mode ) {
        display_msg('Filter mode enabled.');
    }
    else {
        display_msg('Filter mode disabled.');
    }
}

sub next_line ( $self, $key ) {
    $self->set_line( $self->current_line + 1 );
}

sub prev_line ( $self, $key ) {
    $self->set_line( $self->current_line - 1 );
}

sub next_page ( $self, $key ) {
    $self->set_line( $self->current_line + $self->maxlines, $CLEAR );
}

sub prev_page ( $self, $key ) {
    $self->set_line( $self->current_line - $self->maxlines, $CLEAR );
}

sub top ( $self, $key ) {
    $self->set_line( 0, $CLEAR );
}

sub bottom ( $self, $key ) {
    $self->set_line( $self->nlines - $self->maxlines, $CLEAR );
}

sub run ($self) {
    $self->create_pad;
    clear;
    $self->redraw;
    $self->SUPER::redraw;
    $self->SUPER::run;
}

1;
