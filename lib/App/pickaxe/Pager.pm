package App::pickaxe::Pager;
use Mojo::Base -signatures, 'App::pickaxe';
use Curses;
use App::pickaxe::DisplayMsg 'display_msg';

my $CLEAR = 1;

has bindings => sub {
    return {
        'q'               => 'quit',
        Curses::KEY_NPAGE => 'next_page',
        " "               => 'next_page',
        Curses::KEY_PPAGE => 'prev_page',
        Curses::KEY_DOWN  => 'next_line',
        Curses::KEY_UP    => 'prev_line',
    };
};

my @lines;

has subwin => sub {
    my $self = shift;
    return subwin( $stdscr, $self->maxlines, $COLS, 1, 0 );
};

has text => '';

has current_line => 0;

has pad => sub {
    my $self = shift;
    my $cols = $COLS;
    @lines = split( "\n", $self->text );

    for my $line (@lines) {
        if ( length($line) > $cols ) {
            $cols = length($line);
        }
    }

    my $pad = newpad( @lines + 1, $cols );

    my $x = 0;
    for my $line (@lines) {
        addstring( $pad, $x, 0, $line ) or die "addstring: $line\n";
        $x++;
    }
    return $pad;
};

sub DESTROY ($self) {
    $self->pad->delwin;
}

sub redraw ( $self, $clear = 0 ) {
    if ($clear) {
        clear($self->subwin);
        refresh($self->subwin);
    }
    $self->pad->prefresh( $self->current_line, 0, 1, 0, $self->maxlines,
        $COLS - 1 );
}

sub set_line ( $self, $new, $clear = 0 ) {
    $self->current_line($new);
    if ( $self->current_line < 0 ) {
        $self->current_line(0);
    }
    elsif ( $self->current_line > @lines - 1 ) {
        $self->current_line( @lines - 1 );
    }
    $self->redraw($clear);
}

sub next_line ($self) {
    $self->set_line( $self->current_line + 1 );
}

sub prev_line ($self) {
    $self->set_line( $self->current_line - 1 );
}

sub next_page ($self) {
    $self->set_line( $self->current_line + $self->maxlines, $CLEAR );
}

sub prev_page ($self) {
    $self->set_line( $self->current_line - $self->maxlines, $CLEAR );
}

1;
