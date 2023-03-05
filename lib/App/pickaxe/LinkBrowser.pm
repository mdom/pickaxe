package App::pickaxe::LinkBrowser;
use Mojo::Base 'App::pickaxe::UI::Index', -signatures;

has [ 'links', 'api', 'config' ];

has helpbar    => "q:Quit";
has statusbar  => "pickaxe: Link Browser";

sub follow_link ( $self, $key ) {
    my $link = $self->links->[ $self->current_line ];
    if ( $link !~ /^http/ ) {
        my $page = $self->api->page( $link, -1 );
        if ( !$page ) {
            $self->message(qq{Can't find page "$link"});
            return;
        }
        App::pickaxe::Pager->new(
            config => $self->config,
            pages  => App::pickaxe::Pages->new->set( [$page] ),
            api    => $self->api
        )->run;
        return;
    }

    use IPC::Cmd;
    IPC::Cmd::run( command => [ 'xdg-open', $link ] );
}

sub run ($self) {
    $self->on( resize => sub { $self->update_lines } );
    $self->update_lines;
    $self->next::method( $self->config->keybindings );
}

sub update_lines ($self) {
    my $fmt = App::pickaxe::Format->new(
        format     => $self->config->link_format,
        identifier => {
            l => sub { $_[0] },
        },
    );
    $self->set_lines( map { $fmt->printf($_) } @{ $self->links } );
}

1;
