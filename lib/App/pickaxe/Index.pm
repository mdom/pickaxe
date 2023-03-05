package App::pickaxe::Index;
use Mojo::Base -signatures, 'App::pickaxe::Base', 'App::pickaxe::UI::Index';

use App::pickaxe::Getline 'getline';
use App::pickaxe::Keys 'getkey';
use App::pickaxe::Pager;
use App::pickaxe::Pages;
use App::pickaxe::Format;

use Curses;

use POSIX 'strftime';

has helpbar =>
  "q:Quit a:Add e:Edit s:Search /:Find b:Browse o:Order D:Delete ?:Help";

sub statusbar ($self) {
    my $base = $self->api->base_url->clone->query( key => undef );
    return "pickaxe: $base";
}

sub format_time ( $self, $time ) {
    my $strftime_fmt = $self->config->index_time_format;
    my $redmine_fmt  = '%Y-%m-%dT%H:%M:%SZ';

    # return gmtime->strptime( $time, $redmine_fmt )->strftime($strftime_fmt);
    ## This is a microoptimation of the above statement.
    my ( $year, $mon, $mday, $hour, $min, $sec ) = split( /[:TZ-]/, $time );
    $mon  -= 1;
    $year -= 1900;
    strftime( $strftime_fmt, $sec, $min, $hour, $mday, $mon, $year );
}

sub view_page ( $self, $key ) {
    return if $self->empty;
    $self->pages->unsubscribe('changed');
    App::pickaxe::Pager->new(
        config => $self->config,
        pages  => $self->pages,
        api    => $self->api
    )->run;
    ## pages could be changed, so we regenerate the index
    $self->regenerate_index;
    $self->current_line( $self->pages->index );
    $self->pages->on( changed => sub { $self->regenerate_index } );
    $self->render;
}

sub regenerate_index ($self) {
    my $fmt = App::pickaxe::Format->new(
        format     => $self->config->index_format,
        identifier => {
            t => sub { $_[0]->title =~ s/_/ /gr },
            u => sub { $self->format_time( $_[0]->updated_on ) },
            c => sub { $self->format_time( $_[0]->created_on ) },
            v => sub { $_[0]->version },
        },
    );

    $self->set_lines( map { $fmt->printf($_) } $self->pages->each );
    $self->goto_line( $self->pages->index );
}

sub search ( $self, $key ) {
    state $history = [];
    my $query =
      getline( "Search for pages matching: ", { history => $history } );
    if ( $query eq 'all' ) {
        $self->update_pages;
    }
    elsif ( $query eq '' ) {
        $self->message('To view all messages, search for "all".');
    }
    else {
        my $pages = $self->api->search($query);

        if ( !$pages ) {
            $self->message('No matches found.');
            return;
        }
        $self->set_pages($pages);
        $self->message('To view all messages, search for "all".');
    }
}

sub switch_project ( $self, $key ) {
    my %projects = map { $_ => 1 } @{ $self->api->projects };
    state $history = [];
    my $project = getline(
        'Open project: ',
        {
            history            => $history,
            completion_matches => sub ($word) {
                $word ||= '';
                my @completions;
                for my $project ( keys %projects ) {
                    if ( index( $project, $word ) == 0 ) {
                        push @completions, $project;
                    }
                }
                return @completions;
            }
        }
    );
    return if !$project;
    if ( !exists $projects{$project} ) {
        $self->message("$project is not a project.");
        return;
    }

    $self->api->base_url->path("/projects/$project/");
    $self->update_pages;
}

sub sync_pages ( $self, $key ) {
    $self->update_pages;
    $self->message("Updated.");
}

sub run ($self) {
    $self->query_connection_details;

    $self->pages->on( changed => sub { $self->regenerate_index } );
    $self->on( resize => sub { $self->regenerate_index } );
    $self->on( change_line =>
          sub ($self) { $self->pages->set_index( $self->current_line ) } );

    $self->update_pages;

    $self->next::method( $self->config->keybindings );
}

1;
