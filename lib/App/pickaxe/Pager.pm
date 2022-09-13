package App::pickaxe::Pager;
use Mojo::Base -signatures, 'App::pickaxe::Controller';
use Curses;
use App::pickaxe::Getline 'getline';
use IPC::Cmd 'run_forked', 'can_run';
use Mojo::Util 'decode', 'encode';

has help_summary => "q:Quit e:Edit /:find o:Open %:Preview D:Delete ?:help";

has 'config';
has 'pages';

has nlines   => 0;
has ncolumns => 0;

has current_line   => 0;
has current_column => 0;

has 'lines';

has 'matches';

sub status ($self) {
    my $base  = $self->api->base_url->clone->query( key => undef );
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
        $self->reset;
    }
}

sub prev_item ( $self, $key ) {
    my $prev = $self->pages->current;
    $self->pages->prev;
    if ( $prev != $self->pages->current ) {
        $self->reset;
    }
}

sub edit_page ( $self, $key ) {
    $self->next::method($key);
    $self->reset;
}

sub reset ($self) {
    my $text        = $self->api->text_for( $self->pages->current->{title} );
    my $filter_cmd  = $self->config->filter_cmd;
    my $filter_mode = $self->config->filter_mode;
    if ( $text && $filter_mode eq 'yes' && @$filter_cmd ) {
        my $result =
          run_forked( $filter_cmd, { child_stdin => encode( 'utf8', $text ) } );
        if ( $result->{exit_code} == 0 ) {
            $text = decode( 'utf8', $result->{stdout} );
        }
        else {
            $self->message(
                "Can't call " . $filter_cmd->[0] . ": " . $result->{stderr} );
        }
    }
    my @lines = split( "\n", $text );
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

sub redraw ( $self, @ ) {
    $self->next::method;

    my $first_line = $self->current_line;
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
    if ( $self->find_active ) {
        for my $match ( @{ $self->matches } ) {
            next if $match->[0] < $first_line;
            next if $match->[0] > $last_line;
            chgat(
                $match->[0] - $first_line + 1,
                @$match[ 1, 2 ],
                A_REVERSE, 0, 0
            );
        }
    }
}

has find_active => 1;

sub find_toggle ( $self, $key ) {
    $self->find_active( !$self->find_active );
}

## $direction == 1 is forward_search and $directon == -1 is reverse
sub find_next ( $self, $key, $direction = 1 ) {

    if ( !@{$self->matches} ) {
        $self->find($key, $direction);
        return;
    }

    ## find_active is always active with a new search. When we have
    ## matches and find_active is disabled, the user has called find_toggle
    ## before. So we have to toggle it back here.

    if ( @{ $self->matches } && !$self->find_active ) {
        $self->find_active(1);
    }

    my $shifter = $direction == -1 ? \&cycle_shift_reverse : \&cycle_shift;
    while ( $self->matches->[0]->[0] == $self->current_line ) {
        $shifter->( $self->matches );
    }
    $self->set_line( $self->matches->[0]->[0] );

    return;
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
        $self->set_line( $matches[0][0] );
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

sub set_line ( $self, $new ) {
    $self->current_line($new);
    if ( $self->current_line < 0 ) {
        $self->current_line(0);
    }
    elsif ( $self->current_line > $self->nlines - 1 ) {
        $self->current_line( $self->nlines - 1 );
    }
}

sub toggle_filter_mode ( $self, $key ) {
    my $config = $self->config;

    if ( $config->filter_mode eq 'no' ) {
        my $cmd = $config->filter_cmd->[0];
        if ( !can_run($cmd) ) {
            $self->message("$cmd not found.");
            return;
        }
        $config->filter_mode('yes');
    }
    else {
        $config->filter_mode('no');
    }

    $self->reset;
    if ( $config->{filter_mode} eq 'yes' ) {
        $self->message('Filter mode enabled.');
    }
    else {
        $self->message('Filter mode disabled.');
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
    $self->next::method($key);
    $self->reset;
}

sub run ($self) {
    $self->reset;
    $self->next::method;
}

1;
