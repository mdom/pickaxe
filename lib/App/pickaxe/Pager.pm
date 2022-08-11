package App::pickaxe::Pager;
use Mojo::Base -signatures, 'App::pickaxe';
use Curses;
use App::pickaxe::DisplayMsg 'display_msg';

my $CLEAR = 1;

has bindings => sub {
    return {
        'q'                   => 'quit',
        'e'                   => 'edit_page',
        Curses::KEY_NPAGE     => 'next_page',
        " "                   => 'next_page',
        Curses::KEY_PPAGE     => 'prev_page',
        Curses::KEY_DOWN      => 'next_line',
        "\n"                  => 'next_line',
        Curses::KEY_UP        => 'prev_line',
        Curses::KEY_BACKSPACE => 'prev_line',
    };
};

has 'index';

has nlines => 0;

has current_line => 0;

has pad => sub {
    shift->create_pad;
};

sub create_pad ( $self ) {
    my $cols  = $COLS;
    my $text = $self->api->text_for( $self->pages->current->{title} );

    my @lines = split( "\n", $text );

    $self->nlines( @lines + 0 );
    $self->current_line(0);

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
        clear;
        refresh;
        $self->SUPER::redraw;
    }
    $self->pad->prefresh( $self->current_line, 0, 1, 0, $self->maxlines,
        $COLS - 1 );
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

sub next_line ($self, $key) {
    $self->set_line( $self->current_line + 1 );
}

sub prev_line ($self, $key) {
    $self->set_line( $self->current_line - 1 );
}

sub next_page ($self, $key) {
    $self->set_line( $self->current_line + $self->maxlines, $CLEAR );
}

sub prev_page ($self, $key) {
    $self->set_line( $self->current_line - $self->maxlines, $CLEAR );
}

sub run ($self) {
    if ($self->pad) {
        $self->pad->delwin;
    }
    $self->pad( $self->create_pad );
    clear;
    $self->redraw;
    $self->SUPER::redraw;
    $self->SUPER::run;
}

1;
