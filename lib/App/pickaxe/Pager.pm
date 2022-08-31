package App::pickaxe::Pager;
use Mojo::Base -signatures, 'App::pickaxe::Controller';
use Curses;
use App::pickaxe::DisplayMsg 'display_msg';
use App::pickaxe::Getline 'getline';
use IPC::Cmd 'run_forked', 'can_run';
use Mojo::Util 'decode', 'encode';

has help_summary => "q:Quit e:Edit /:find o:Open %:Preview D:Delete ?:help";

has map => 'pager';
has 'config';
has 'pages';

has bindings => sub {
    return {
        'q'           => 'quit',
        'e'           => 'edit_page',
        'w'           => 'create_page',
        '<PageDown>'  => 'next_page',
        '<Space>'     => 'next_page',
        '<PageUp>'    => 'prev_page',
        '<Down>'      => 'next_line',
        '<Up>'        => 'prev_line',
        '<Return>'    => 'next_line',
        '<Backspace>' => 'prev_line',
        '<Resize>'    => 'redraw',
        '%'           => 'toggle_filter_mode',
        '<Home>'      => 'top',
        '<End>'       => 'bottom',
        '<Left>'      => 'scroll_left',
        '<Right>'     => 'scroll_right',
        '/'           => 'find',
        'n'           => 'find_next',
        '<Backslash>' => 'find_toggle',
        o             => 'open_in_browser',
        J => 'next_item',
        K => 'prev_item',
        D => 'delete_page',
    };
};

has 'index';

has nlines   => 0;
has ncolumns => 0;

has current_line   => 0;
has current_column => 0;

has 'lines';

has 'pad';

has 'needle';
has 'matches';

sub status ($self) {
    my $base  = $self->config->{base_url}->clone->query( key => undef );
    my $title = $self->pages->current->{title};
    my $percent;
    if ( $self->nlines == 0 ) {
        $percent = '100';
    }
    else {
        $percent = int( $self->current_line / $self->nlines * 100 );
    }
    return "pickaxe: $base $title", sprintf( "--%3d%%", $percent );
}

sub next_item ( $self, $key ) {
    my $prev = $self->pages->current;
    $self->pages->next;
    if ( $prev != $self->pages->current ) {
        $self->update_pad;
    }
}

sub prev_item ( $self, $key ) {
    my $prev = $self->pages->current;
    $self->pages->prev;
    if ( $prev != $self->pages->current ) {
        $self->update_pad;
    }
}

sub edit_page ( $self, $key ) {
    $self->SUPER::edit_page($key);
    $self->update_pad;
    $self->redraw;
}

sub update_pad ($self) {
    if ( $self->pad ) {
        $self->pad->delwin;
    }
    my $cols = $COLS;
    my $text = $self->api->text_for( $self->pages->current->{title} );

    my $filter_cmd = $self->config->filter_cmd;
    my $filter_mode = $self->config->filter_mode;
    if ( $text && $filter_mode eq 'yes' && @$filter_cmd ) {
        my $result =
          run_forked( $filter_cmd, { child_stdin => encode( 'utf8', $text ) } );

        if ( $result->{exit_code} == 0 ) {
            $text = decode( 'utf8', $result->{stdout} );
        }
        else {
            display_msg(
                "Can't call " . $filter_cmd->[0] . ": " . $result->{stderr} );
        }
    }

    my @lines = split( "\n", $text );

    $self->nlines( @lines + 0 );
    $self->lines( \@lines );
    $self->current_line(0);
    $self->current_column(0);

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
    $self->redraw;
}

sub DESTROY ($self) {
    if ( $self->pad ) {
        $self->pad->delwin;
    }
}

sub redraw ( $self, @) {
    erase;
    $self->SUPER::redraw;
    noutrefresh(stdscr);
    pnoutrefresh( $self->pad, $self->current_line, $self->current_column, 1, 0,
        $self->maxlines, $COLS - 1 );
    doupdate;
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

    $self->redraw;
}

sub set_line ( $self, $new ) {
    $self->current_line($new);
    if ( $self->current_line < 0 ) {
        $self->current_line(0);
    }
    elsif ( $self->current_line > $self->nlines - 1 ) {
        $self->current_line( $self->nlines - 1 );
    }
    $self->redraw;
}

sub toggle_filter_mode ( $self, $key ) {
    my $config = $self->config;

    if ( $config->filter_mode eq 'no' ) {
        my $cmd = $config->filter_cmd->[0];
        if ( !can_run($cmd) ) {
            display_msg("$cmd not found.");
            return;
        }
        $config->filter_mode('yes');
    }
    else {
        $config->filter_mode('no');
    }

    $self->update_pad;
    if ( $config->{filter_mode} eq 'yes' ) {
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
    $self->set_line( $self->current_line + $self->maxlines );
}

sub prev_page ( $self, $key ) {
    $self->set_line( $self->current_line - $self->maxlines );
}

sub top ( $self, $key ) {
    $self->set_line(0);
}

sub bottom ( $self, $key ) {
    $self->set_line( $self->nlines - $self->maxlines );
}

sub delete_page ( $self, $key ) {
    $self->SUPER::delete_page( $key );
    $self->update_pad;
}

sub run ($self) {
    $self->update_pad;
    $self->SUPER::redraw;
    $self->SUPER::run;
}

1;
