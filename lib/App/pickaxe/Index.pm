package App::pickaxe::Index;
use Mojo::Base -signatures, 'App::pickaxe::Controller';
use Curses;
use App::pickaxe::Pager;
use App::pickaxe::ArrayIterator;
use App::pickaxe::Getline 'getline';
use App::pickaxe::DisplayMsg 'display_msg';
use Mojo::Date;
use POSIX 'strftime';

has pad => sub {
    shift->create_pad;
};

has pager => sub ($self) {
    App::pickaxe::Pager->new( state => $self->state )->run;
};

has bindings => sub {
    return {
        Curses::KEY_END   => 'last_item',
        Curses::KEY_HOME  => 'first_item',
        Curses::KEY_DOWN  => 'next_item',
        Curses::KEY_UP    => 'prev_item',
        j                 => 'next_item',
        k                 => 'prev_item',
        e                 => 'edit_page',
        n                 => 'create_page',
        o                 => 'open_in_browser',
        "\n"              => 'view_page',
        Curses::KEY_NPAGE => 'next_page',
        Curses::KEY_PPAGE => 'prev_page',
        Curses::KEY_LEFT  => 'prev_page',
        Curses::KEY_RIGHT => 'next_page',
        ' '               => 'next_page',
        s                 => 'search',
        '?'               => 'display_help',
        '$'               => 'update_pages',
        q                 => 'quit',
        1                 => 'jump',
        2                 => 'jump',
        3                 => 'jump',
        4                 => 'jump',
        5                 => 'jump',
        6                 => 'jump',
        7                 => 'jump',
        8                 => 'jump',
        9                 => 'jump',
        0                 => 'jump',
    };
};

sub select ( $self, $new ) {
    return if !$self->pad;
    my $pages = $self->state->pages;
    $pages->seek($new);

    if ( $pages->oldpos != $pages->pos ) {
        $self->pad->chgat( $pages->oldpos, 0, -1, A_NORMAL, 0, 0 );
    }
    my $clear =
      $self->first_item_on_page( $pages->oldpos ) !=
      $self->first_item_on_page( $pages->pos );
    $self->update_pad($clear);
}

sub create_pad ($self) {
    my $pages = $self->state->pages;
    if ( !$pages->count ) {
        return;
    }

    my $pad = newpad( $pages->count, $COLS );
    my $x   = 0;
    for my $page ( $pages->each ) {
        my $len_counter = length( $pages->count );
        my $line        = sprintf(
            "%${len_counter}d   %s   %-s",
            ( $x + 1 ),
            strftime(
                "%Y-%m-%d %H:%M:%S",
                gmtime Mojo::Date->new( $page->{updated_on} )->epoch
            ),
            $page->{title},
        );
        $line = substr( $line, 0, $COLS - 1 );
        $pad->addstring( $x, 0, $line );
        $x++;
    }
    return $pad;
}

sub update_pad ( $self, $clear ) {
    return if !$self->pad;
    my $pages = $self->state->pages;
    $self->pad->chgat( $pages->pos, 0, -1, A_REVERSE, 0, 0 );

    my $offset = int( $pages->pos / $self->maxlines ) * $self->maxlines;
    if ($clear) {
        clear;
        $self->update_statusbar;
        $self->update_helpbar;
        refresh;
    }
    prefresh( $self->pad, $offset, 0, 1, 0, $LINES - 3, $COLS - 1 );
}

sub update_pages ( $self, $key ) {
    $self->set_pages( $self->api->pages );
    display_msg("Updated.");
}

sub jump ( $self, $key ) {
    return if !$self->pad;
    my $number = getline( "Jump to wiki page: ", { buffer => $key } );
    if ( $number =~ /\D/ ) {
        display_msg("Argument must be a number.");
        return;
    }
    $self->select( $number - 1 );
}

sub view_page ( $self, $key ) {
    return if !$self->pad;
    $self->pager->run;
    $self->update_pad(1);
    $self->update_statusbar;
    $self->update_helpbar;
}

sub prev_page ( $self, $key ) {
    return if !$self->pad;
    my $pages = $self->state->pages;
    my $last_item_on_page =
      int( $pages->pos / $self->maxlines ) * $self->maxlines - 1;
    if ( $last_item_on_page < 0 ) {
        $self->select(0);
    }
    else {
        $self->select($last_item_on_page);
    }
}

sub first_item_on_page ( $self, $selected ) {
    return int( $selected / $self->maxlines ) * $self->maxlines;
}

sub next_item ( $self, $key ) {
    return if !$self->pad;
    $self->select( $self->state->pages->pos + 1 );
}

sub prev_item ( $self, $key ) {
    return if !$self->pad;
    $self->select( $self->state->pages->pos - 1 );
}

sub first_item ( $self, $key ) {
    return if !$self->pad;
    $self->select(0);
}

sub last_item ( $self, $key ) {
    return if !$self->pad;
    $self->select( $self->state->pages->count - 1 );
}

sub next_page ( $self, $key ) {
    return if !$self->pad;
    my $first_item_on_page =
      int( $self->pages->pos / $self->maxlines ) * $self->maxlines;
    if ( $self->pages->count > $first_item_on_page + $self->maxlines ) {
        $self->select( $first_item_on_page + $self->maxlines );
    }
    else {
        $self->select( $self->pages->count - 1 );
    }
}

has 'order' => 'revdate';

sub set_pages ( $self, $pages ) {

    if ( $self->order eq 'revdate' ) {
        $pages = [ sort { $b->{updated_on} cmp $a->{updated_on} } @$pages ];
    }

    $self->state->pages( App::pickaxe::ArrayIterator->new( $pages ));
    if ( $self->pad ) {
        $self->pad->delwin;
    }
    $self->pad( $self->create_pad );
    $self->update_pad(1);
}

sub search ( $self, $key ) {
    my $query = getline("Search for pages matching: ");
    if ( $query eq 'all' ) {
        $self->set_pages( $self->api->pages );
    }
    elsif ( $query eq '' ) {
        display_msg('To view all messages, search for "all".');
    }
    else {
        my $pages = $self->api->search($query);

        if ( !$pages ) {
            display_msg('No matches found.');
            return;
        }
        $self->set_pages($pages);
        display_msg('To view all messages, search for "all".');
    }
}

sub run ($self) {
    $self->SUPER::redraw;
    $self->query_connection_details;
    $self->set_pages( $self->api->pages );
    $self->SUPER::run;
}

1;
