package App::pickaxe::Index;
use Mojo::Base -signatures, 'App::pickaxe';
use Curses;
use App::pickaxe::Pager;

has selected => 0;

has pages => sub {
    shift->list_pages;
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
        s                 => 'search',
        '?'               => 'display_help',
        q                 => 'quit',
    };
};

sub create_pad ($self) {
    my @pages = @{ $self->pages };
    if ( !@pages ) {
        return;
    }
    my $pad = newpad( scalar @pages, $COLS );
    for my $page (@pages) {
        $pad->addstring( $page->{title} . "\n" );
    }
    return $pad;
}

sub list_pages ($self) {
    my $res = eval { $self->api->get( $self->base->clone->path("wiki/index.json") ) };
    if ($@) {
        endwin;
        die "Error connection server: " . $@ . "\n";
    }
    if ( !$res->is_success ) {
        endwin;
        die "Error connection server: " . $res->message . "\n";
    }
    return $res->json->{wiki_pages};
}

sub update_pad ( $self, $clear ) {
    return if !$self->pad;
    $self->pad->chgat( $self->selected, 0, -1, A_REVERSE, 0, 0 );

    my $offset = int( $self->selected / $self->maxlines ) * $self->maxlines;
    if ($clear) {
        clear;
        $self->update_statusbar;
        $self->update_helpbar;
        refresh;
    }
    prefresh( $self->pad, $offset, 0, 1, 0, $LINES - 3, $COLS - 1 );
}

sub view_page ($self) {
    my $page = $self->pages->[ $self->selected ]->{title};
    my $res  = $self->api->get( $self->base->clone->path("wiki/$page.json") );
    if ( !$res->is_success ) {
        $self->display_msg( "Can't retrieve $page: " . $res->msg );
        return;
    }
    my $text = $res->json->{wiki_page}->{text};
    App::pickaxe::Pager->new( text => $text )->run;
    $self->update_pad(1);
    $self->update_statusbar;
    $self->update_helpbar;
}

sub prev_page ($self) {
    return if !$self->pad;
    my $last_item_on_page =
      int( $self->selected / $self->maxlines ) * $self->maxlines - 1;
    if ( $last_item_on_page < 0 ) {
        $self->set_selected(0);
    }
    else {
        $self->set_selected($last_item_on_page);
    }
}

sub set_selected ($self,$new) {
    return if !$self->pad;
    my $prev_selected = $self->selected;
    $self->selected( $new );
    if ( $self->selected < 0 ) {
        $self->selected(0);
    }
    elsif ( $self->selected > @{$self->pages} - 1 ) {
        $self->selected(@{$self->pages} - 1);
    }
    if ( $prev_selected != $self->selected ) {
        $self->pad->chgat( $prev_selected, 0, -1, A_NORMAL, 0, 0 );
    }
    my $clear =
      $self->first_item_on_page($prev_selected) != $self->first_item_on_page($self->selected);
    $self->update_pad($clear);
}

sub first_item_on_page ($self, $selected) {
    return int( $selected / $self->maxlines ) * $self->maxlines;
}

sub next_item ($self) {
    return if !$self->pad;
    $self->set_selected( $self->selected + 1 );
}

sub prev_item ($self) {
    return if !$self->pad;
    $self->set_selected( $self->selected - 1 );
}

sub next_page ($self) {
    return if !$self->pad;
    my $first_item_on_page =
      int( $self->selected / $self->maxlines ) * $self->maxlines;
    if ( @{ $self->pages } > $first_item_on_page + $self->maxlines ) {
        $self->set_selected( $first_item_on_page + $self->maxlines );
    }
    else {
        $self->set_selected( @{ $self->pages } - 1 );
    }
}

sub search ($self) {
    my $query = getline("Search for pages matching: ");
    if ( $query eq 'all' ) {
        $self->pages = self->list_pages;
        $self->update_pad(1);
    }
    elsif ( $query eq '' ) {
        $self->display_msg('To view all messages, search for "all".');
    }
    else {
        my $url = $self->base->clone->path("search.json");
        $url->query->merge( q => $query, wiki_pages => 1 );
        my $res     = $self->api->get($url);
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
        $self->selected = 0;
        $self->update_pad(1);
    }
}

sub run ($self) {
    $self->query_connection_details;
    $self->update_pad(1);
    $self->SUPER::run;
}

1;
