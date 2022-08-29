package App::pickaxe::Index;
use Mojo::Base -signatures, 'App::pickaxe::Controller';
use Curses;
use App::pickaxe::Pager;
use App::pickaxe::Pages;
use App::pickaxe::Getline 'getline';
use App::pickaxe::DisplayMsg 'display_msg';
use App::pickaxe::SelectOption 'select_option', 'askyesno';
use POSIX 'strftime';

has 'pad';
has map => 'index';
has 'config';
has pages => sub { App::pickaxe::Pages->new; };

has pager => sub ($self) {
    App::pickaxe::Pager->new( pages => $self->pages, config => $self->config  );
};

has help_summary =>
  "q:Quit a:Add e:Edit s:Search /:find b:Browse o:Order D:delete ?:help";

has 'order' => 'reverse_updated_on';

has bindings => sub {
    return {
        '<End>'      => 'last_item',
        '<Home>'     => 'first_item',
        '<Down>'     => 'next_item',
        '<Up>'       => 'prev_item',
        j            => 'next_item',
        k            => 'prev_item',
        e            => 'edit_page',
        a            => 'add_page',
        b            => 'open_in_browser',
        '<Return>'   => 'view_page',
        '<PageDown>' => 'next_page',
        '<PageUp>'   => 'prev_page',
        '<Left>'     => 'prev_page',
        '<Right>'    => 'next_page',
        '<Space>'    => 'next_page',
        s            => 'search',
        o            => 'set_order',
        O            => 'set_reverse_order',
        D            => 'delete_page',
        '/'          => 'find',
        'n'          => 'find_next',
        'p'          => 'find_next',
        '?'          => 'display_help',
        '$'          => 'update_pages',
        q            => 'quit',
        1            => 'jump',
        2            => 'jump',
        3            => 'jump',
        4            => 'jump',
        5            => 'jump',
        6            => 'jump',
        7            => 'jump',
        8            => 'jump',
        9            => 'jump',
        0            => 'jump',
    };
};

has index_time_format => "%Y-%m-%d %H:%M:%S";
has index_format      => '%4n %-22u %t';

sub status ($self) {
    my $base = $self->config->{base_url}->clone->query( key => undef );
    return "pickaxe: $base";
}

sub remove_selection ($self) {
    $self->pad->chgat( $self->pages->pos, 0, -1, A_NORMAL, 0, 0 );
}

sub add_selection ( $self ) {
    $self->pad->chgat( $self->pages->pos, 0, -1, A_REVERSE, 0, 0 );
}

sub select ( $self, $new ) {
    return if !$self->pad;
    my $pages = $self->pages;
    if ( $new != $pages->pos ) {
        $self->remove_selection;
    }
    $pages->seek($new);

    my $clear =
      $self->first_item_on_page( $pages->oldpos ) !=
      $self->first_item_on_page( $pages->pos );
    $self->refresh_pad($clear);
}

sub format_time ( $self, $time ) {
    my $strftime_fmt = $self->index_time_format;
    my $redmine_fmt  = '%Y-%m-%dT%H:%M:%SZ';

    # return gmtime->strptime( $time, $redmine_fmt )->strftime($strftime_fmt);
    ## This is a microoptimation of the above statement.
    my ( $year, $mon, $mday, $hour, $min, $sec ) = split( /[:TZ-]/, $time );
    $mon  -= 1;
    $year -= 1900;
    strftime( $strftime_fmt, $sec, $min, $hour, $mday, $mon, $year );
}

sub compile_index_format ($self) {
    my $index_fmt = $self->index_format;

    my $fmt = '';
    my @args;

    my %identifier = (
        n => [ d => sub { $_[0]->{index} + 1 } ],
        t => [ s => sub { my $t = $_[0]->{title}; $t =~ s/_/ /g; $t } ],
        u => [ s => sub { $self->format_time( $_[0]->{'updated_on'} ) } ],
        c => [ s => sub { $self->format_time( $_[0]->{'created_on'} ) } ],
        v => [ s => sub { $_[0]->{version} } ],
    );

    while (1) {
        if ( $index_fmt =~ /\G%(-?\d+(?:.\d)?)?([a-zA-Z])/gc ) {
            my ( $mod, $format ) = ( $1, $2 );
            $mod //= '';
            if ( my $i = $identifier{$format} ) {
                $fmt .= "%$mod" . $i->[0];
                push @args, $i->[1];
            }
            else {
                die "Unknown format specifier <$format>\n";
            }
        }
        elsif ( $index_fmt =~ /\G([^%]+)/gc ) {
            $fmt .= $1;
        }
        elsif ( $index_fmt =~ /\G$/gc ) {
            last;
        }
    }
    return $fmt, @args;
}

sub update_pad ($self) {
    my $pages = $self->pages;
    if ( $self->pad ) {
        $self->pad->delwin;
    }
    if ( !$pages->count ) {
        return;
    }

    my $pad = newpad( $pages->count, $COLS );
    my $x   = 0;
    my ( $fmt, @args ) = $self->compile_index_format;
    for my $page ( $pages->each ) {
        $page->{index} = $x;

        my $line = sprintf( $fmt, map { $page->$_ } @args );
        $line = substr( $line, 0, $COLS - 1 );
        $pad->addstring( $x, 0, $line );
        $x++;
    }
    $self->pad( $pad );
    $self->refresh_pad(1);
}

sub refresh_pad ( $self, $clear ) {
    return if !$self->pad;
    my $pages = $self->pages;
    $self->add_selection;

    my $offset = int( $pages->pos / $self->maxlines ) * $self->maxlines;
    if ($clear) {
        clear;
        $self->update_statusbar;
        $self->update_helpbar;
        refresh;
    }
    prefresh( $self->pad, $offset, 0, 1, 0, $LINES - 3, $COLS - 1 );
}

sub delete_page ( $self, $key ) {
    display_msg "There are no pages." if !$self->pad;
    $self->SUPER::delete_page($key);
    $self->update_pad;
}

sub update_pages ( $self, $key ) {
    $self->set_pages( $self->api->pages );
    display_msg("Updated.");
}

has 'needle';
has 'find_history' => sub { [] };

sub find_next ( $self, $key ) {
    display_msg "There are no pages." if !$self->pad;
    if ( !$self->needle ) {
        my $needle =
          getline( "Find title: ", { history => $self->find_history } );
        return if !$needle;
        $needle = lc($needle);
        $self->needle($needle);
    }
    my $needle = $self->needle;
    my @pages  = $self->pages->each;
    my $pos    = $self->pages->pos;
    for my $i ( $pos + 1 .. @pages - 1, 0 .. $pos - 1 ) {
        my $page = $pages[$i];
        if ( index( lc( $page->{title} ), $needle ) != -1 ) {
            $self->select( $page->{index} );
            return;
        }
    }
    display_msg "Not found.";
    return;
}

my %sort_options = (
    updated => 'updated_on',
    created => 'created_on',
    title   => 'title',
);

sub set_order ( $self, $key ) {
    my $order = select_option( 'Sort', qw(Updated Created Title) );
    if ($order) {
        $self->order( $sort_options{$order} );
        $self->set_pages( $self->pages->array );
    }
}

sub set_reverse_order ( $self, $key ) {
    my $order = select_option( 'Rev-Sort', qw(Updated Created Title) );
    if ($order) {
        $self->order("reverse_$sort_options{$order}");
        $self->set_pages( $self->pages->array );
    }
}

sub find ( $self, $key ) {
    display_msg "There are no pages." if !$self->pad;
    $self->needle('');
    $self->find_next($key);
}

sub jump ( $self, $key ) {
    return if !$self->pad;
    my $number = getline( "Jump to wiki page: ", { buffer => $key } );
    if ( !$number || $number =~ /\D/ ) {
        display_msg("Argument must be a number.");
        return;
    }
    $self->select( $number - 1 );
}

sub view_page ( $self, $key ) {
    return if !$self->pad;
    $self->remove_selection;

    $self->pager->run;

    $self->update_pad;
    $self->update_statusbar;
    $self->update_helpbar;
}

sub prev_page ( $self, $key ) {
    return if !$self->pad;
    my $pages = $self->pages;
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
    $self->select( $self->pages->pos + 1 );
}

sub prev_item ( $self, $key ) {
    return if !$self->pad;
    $self->select( $self->pages->pos - 1 );
}

sub first_item ( $self, $key ) {
    return if !$self->pad;
    $self->select(0);
}

sub last_item ( $self, $key ) {
    return if !$self->pad;
    $self->select( $self->pages->count - 1 );
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

sub set_pages ( $self, $pages ) {

    my $order = $self->order =~ s/^reverse_//r;

    $pages = [ sort { $a->{$order} cmp $b->{$order} } @$pages ];

    if ( $self->order =~ /^reverse_/ ) {
        $pages = [ reverse @$pages ];
    }

    $self->pages->replace( $pages );

    $self->update_pad;
}

sub search ( $self, $key ) {
    my $query = getline( "Search for pages matching: ",
        { history => $self->find_history } );
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
