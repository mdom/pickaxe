package App::pickaxe::Pager;
use Mojo::Base -signatures, 'App::pickaxe::Controller';
use Curses;
use App::pickaxe::DisplayMsg 'display_msg';
use IPC::Cmd 'run_forked';
use Mojo::Util 'decode', 'encode';

my $CLEAR = 1;

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
        Curses::KEY_LEFT      => 'scroll_left',
        Curses::KEY_RIGHT     => 'scroll_right',
    };
};

has 'index';

has filter_mode => 0;

has filter => sub { [ 'pandoc', '-f', 'textile', '-t', 'plain' ] };

has nlines   => 0;
has ncolumns => 0;

has current_line   => 0;
has current_column => 0;

has 'pad';

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

    if ( $self->filter_mode ) {
        $text = encode( 'utf8', $text );
        my $result = run_forked( $self->filter, { child_stdin => $text } );
        $text = decode( 'utf8', $result->{stdout} );
    }

    my @lines = split( "\n", $text );

    $self->nlines( @lines + 0 );
    $self->current_line(0);

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
    $self->pad->delwin;
}

sub redraw ( $self, $clear = 0 ) {
    if ($clear) {
        clear;
        refresh;
        $self->SUPER::redraw;
    }
    $self->pad->prefresh( $self->current_line, $self->current_column, 1, 0,
        $self->maxlines, $COLS - 1 );
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

sub run ($self) {
    $self->create_pad;
    clear;
    $self->redraw;
    $self->SUPER::redraw;
    $self->SUPER::run;
}

1;
