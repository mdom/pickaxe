package App::pickaxe::Index;
use Mojo::Base -signatures, 'App::pickaxe';
use Curses;
use App::pickaxe::Pager;
use App::pickaxe::Wiki;
use App::pickaxe::Getline 'getline';
use App::pickaxe::DisplayMsg 'display_msg';

has 'wiki' => sub {
    App::pickaxe::Wiki->new( api => shift->api);
};

has pad => sub {
    shift->create_pad;
};

has bindings => sub {
    return {
        Curses::KEY_DOWN  => 'next_item',
        Curses::KEY_UP    => 'prev_item',
        n                 => 'next_item',
        p                 => 'prev_item',
        e                 => 'edit_page',
        "\n"              => 'view_page',
        Curses::KEY_NPAGE => 'next_page',
        Curses::KEY_PPAGE => 'prev_page',
        Curses::KEY_LEFT  => 'prev_page',
        Curses::KEY_RIGHT => 'next_page',
        ' '               => 'next_page',
        s                 => 'search',
        '?'               => 'display_help',
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

sub select ($self, $new) {
    return if !$self->pad;
    $self->wiki->select($new);

    if ( $self->wiki->prev_selected != $self->wiki->selected ) {
        $self->pad->chgat( $self->wiki->prev_selected, 0, -1, A_NORMAL, 0, 0 );
    }
    my $clear =
      $self->first_item_on_page($self->wiki->prev_selected) !=
      $self->first_item_on_page( $self->wiki->selected );
    $self->update_pad($clear);
}

sub create_pad ($self) {
    my @pages = @{ $self->wiki->pages };
    if ( !@pages ) {
        return;
    }
    my $pad = newpad( scalar @pages, $COLS );
    my $x   = 0;
    for my $page (@pages) {
        my $len_counter = length( @pages + 0 );
        my $len_title   = $COLS - $len_counter;
        my $line        = sprintf(
            "%${len_counter}d %-${len_title}s",
            ( $x + 1 ),
            $page->{title},
        );
        $pad->addstring( $x, 0, $line );
        $x++;
    }
    return $pad;
}

sub update_pad ( $self, $clear ) {
    return if !$self->pad;
    $self->pad->chgat( $self->wiki->selected, 0, -1, A_REVERSE, 0, 0 );

    my $offset = int( $self->wiki->selected / $self->maxlines ) * $self->maxlines;
    if ($clear) {
        clear;
        $self->update_statusbar;
        $self->update_helpbar;
        refresh;
    }
    prefresh( $self->pad, $offset, 0, 1, 0, $LINES - 3, $COLS - 1 );
}

sub jump ($self, $key) {
   my $number = getline("Jump to wiki page: ", { buffer => $key }); 
   if ($number =~ /\D/ ) {
       display_msg("Argument must be a number.");
       return;
   }
   $self->select($number - 1);
}

sub view_page ($self, $key) {
    my $title = $self->wiki->current_page->{title};
    my $res  = $self->api->get( "wiki/$title.json" );
    if ( !$res->is_success ) {
        $self->display_msg( "Can't retrieve $title: " . $res->msg );
        return;
    }
    my $text = $res->json->{wiki_page}->{text};
    App::pickaxe::Pager->new( text => $text )->run;
    $self->update_pad(1);
    $self->update_statusbar;
    $self->update_helpbar;
}

sub prev_page ($self, $key) {
    return if !$self->pad;
    my $last_item_on_page =
      int( $self->wiki->selected / $self->maxlines ) * $self->maxlines - 1;
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

sub next_item ($self, $key) {
    return if !$self->pad;
    $self->select( $self->wiki->selected + 1 );
}

sub prev_item ($self, $key) {
    return if !$self->pad;
    $self->select( $self->wiki->selected - 1 );
}

sub next_page ($self, $key) {
    return if !$self->pad;
    my $first_item_on_page =
      int( $self->wiki->selected / $self->maxlines ) * $self->maxlines;
    if ( @{ $self->wiki->pages } > $first_item_on_page + $self->maxlines ) {
        $self->select( $first_item_on_page + $self->maxlines );
    }
    else {
        $self->select( @{ $self->wiki->pages } - 1 );
    }
}

sub search ($self, $key) {
    my $query = getline("Search for pages matching: ");
    if ( $query eq 'all' ) {
        $self->wiki->refresh;
        $self->update_pad(1);
    }
    elsif ( $query eq '' ) {
        $self->display_msg('To view all messages, search for "all".');
    }
    else {
        my $res     = $self->api->get("search.json", q => $query, wiki_pages => 1);
        my @results = @{ $res->json->{results} };

        my @found;
        if ( !@results ) {
            self->display_msg('No matches found.');
            return;
        }

        my %pages = map { $_->{title} => $_ } @{ $self->pages };

        for my $result (@results) {
            $result->{title} =~ s/^Wiki: //;
            push @found, $pages{ $result->{title} };
        }
        $self->pages = \@found;
        if ( $self->pad ) {
            $self->pad->delwin;
        }
        $self->pad      = self->create_pad;
        $self->select(0);
        $self->update_pad(1);
    }
}

sub run ($self) {
    $self->query_connection_details;
    $self->update_pad(1);
    $self->SUPER::run;
}

1;
