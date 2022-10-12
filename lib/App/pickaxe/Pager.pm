package App::pickaxe::Pager;
use Mojo::Base -signatures, 'App::pickaxe::Controller';
use Curses;
use App::pickaxe::Getline 'getline';
use Mojo::Util 'decode', 'encode';
use Text::Wrap 'wrap';
use Mojo::Util 'html_unescape';

has help_summary => "q:Quit e:Edit /:find o:Open %:Preview D:Delete ?:help";

has 'config';
has 'pages';
has 'lines';
has 'matches';

has nlines         => 0;
has ncolumns       => 0;
has current_line   => 0;
has current_column => 0;
has find_active    => 1;

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

sub render_text ($self, $text) {

    ## Move <pre> to it's own line
    $text =~ s/^(\S+)(<\/?pre>)/$1\n$2/gms;
    $text =~ s/(<\/?pre>)(\S+)$/$1\n$2/gms;

    ## Remove empty lists
    $text =~ s/^\s*[\*\#]\s*\n//gmsx;

    ## Unscape html entities
    $text = html_unescape($text);

    # Remove header ids
    $text =~ s/^h(\d)\(.*?\)\./h$1./gms;

    ## Collapse empty lines;
    $text =~ s/\n{3,}/\n\n\n/gs;

    my $pre_mode = 0;
    my @lines;
    for my $line ( split( "\n", $text )) {
        if ( $line =~ /<pre>/) {
            $pre_mode = 1;
        }
        elsif ( $line =~ /<\/pre>/) {
            $pre_mode = 0;
        }
        elsif ( $pre_mode ) {
            push @lines, "    " . $line;
        }
        elsif ( $line =~ /^(\s*[\*\#]\s*)\S/ ) { 
            push @lines, split("\n",  wrap('', ' ' x length($1), $line)); 
        }
        elsif ( $line eq '' ) {
            push @lines, $line;
        }
        else {
            $line =~ /^(\s*)/;
            push @lines, split("\n",  wrap($1, $1, $line)); 
        }
    }
    return @lines;
};

sub reset ($self) {
    my @lines = $self->render_text( $self->pages->current->text );
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

sub find_toggle ( $self, $key ) {
    $self->find_active( !$self->find_active );
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
