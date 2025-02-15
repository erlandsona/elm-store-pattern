module Store exposing
    ( Store, init
    , Action, Msg(..), update
    , ToastMsg, createPost, getImage, getPosts, getUsers
    )

{-|

@docs Store, init
@docs Action, Msg, update

-}

import API.Image exposing (Image, ImageId)
import API.Post exposing (Post, PostCreateData, PostId)
import API.User exposing (User, UserId)
import Dict exposing (Dict)
import Http
import RemoteData exposing (RemoteData(..), WebData)


type alias Store =
    { -- we're loading all posts at once
      -- GET /api/posts
      posts : WebData (Dict PostId Post)
    , -- we're loading all users at once
      -- GET /api/users/
      users : WebData (Dict UserId User)
    , -- we're lazy loading images as needed
      -- GET /api/images/<ID>
      images : Dict ImageId (WebData Image)
    }


{-| As in, Request
-}
type alias Action =
    { run : Store -> ( Store, Cmd Msg )
    , toastOnSent : Maybe String
    }


type alias ToastMsg =
    { onFailure : String
    , onSuccess : Maybe String
    }


base : Action
base =
    { run = \store -> ( store, Cmd.none )
    , toastOnSent = Nothing
    }


getPosts : Action
getPosts =
    { base
        | run =
            \store ->
                if shouldSendRequest store.posts then
                    ( { store | posts = Loading }
                    , send "Failed to get posts"
                        (\err s -> { s | posts = Failure err })
                        API.Post.getAll
                        GotPosts
                    )

                else
                    ( store, Cmd.none )
    }


getUsers : Action
getUsers =
    { base
        | run =
            \store ->
                if shouldSendRequest store.users then
                    ( { store | users = Loading }
                    , send "Failed to get users"
                        (\err s -> { s | users = Failure err })
                        API.User.getAll
                        GotUsers
                    )

                else
                    ( store, Cmd.none )
    }


getImage : ImageId -> Action
getImage imageId =
    { base
        | run =
            \store ->
                if shouldSendRequest_ (Dict.get imageId store.images) then
                    ( { store | images = Dict.insert imageId Loading store.images }
                    , send ("Failed to get image '" ++ imageId ++ "'")
                        (\err s ->
                            { s | images = Dict.insert imageId (Failure err) store.images }
                        )
                        (API.Image.get imageId)
                        GotImage
                    )

                else
                    ( store, Cmd.none )
    }


createPost : PostCreateData -> Action
createPost postCreateData =
    { run =
        \store ->
            ( store
            , send ("Failed to create post '" ++ postCreateData.title ++ "'")
                (\_ s -> s)
                (API.Post.create postCreateData)
                (CreatedPost ("Created post '" ++ postCreateData.title ++ "'"))
            )
    , toastOnSent = Just ("Creating post '" ++ postCreateData.title ++ "'")
    }


{-| As in, Response
-}
type Msg
    = HttpError String Http.Error (Store -> Store) -- !
    | GotPosts (List Post)
    | GotUsers (List User)
    | GotImage Image
    | CreatedPost String Post


init : Store
init =
    { posts = NotAsked
    , users = NotAsked
    , images = Dict.empty
    }


shouldSendRequest : WebData a -> Bool
shouldSendRequest webdata =
    case webdata of
        NotAsked ->
            True

        Loading ->
            False

        Failure _ ->
            False

        Success _ ->
            False


shouldSendRequest_ : Maybe (WebData a) -> Bool
shouldSendRequest_ maybeWebdata =
    case maybeWebdata of
        Nothing ->
            True

        Just webdata ->
            shouldSendRequest webdata


send : String -> (Http.Error -> Store -> Store) -> ((Result Http.Error a -> Msg) -> Cmd Msg) -> (a -> Msg) -> Cmd Msg
send toasts onErr toCmd toSuccessMsg =
    toCmd
        (\result ->
            case result of
                Err err ->
                    HttpError toasts err (onErr err)

                Ok success ->
                    toSuccessMsg success
        )


update : Msg -> Store -> ( Store, Cmd Msg )
update msg store =
    case msg of
        GotPosts posts ->
            ( { store | posts = Success (dictByIds posts) }
            , Cmd.none
            )

        GotUsers users ->
            ( { store | users = Success (dictByIds users) }
            , Cmd.none
            )

        GotImage image ->
            ( { store | images = Dict.insert image.id (Success image) store.images }
            , Cmd.none
            )

        CreatedPost _ post ->
            ( { store | posts = RemoteData.map (Dict.insert post.id post) store.posts }
            , Cmd.none
            )

        HttpError _ _ saveFailure ->
            ( saveFailure store
            , Cmd.none
            )


dictByIds : List { a | id : String } -> Dict String { a | id : String }
dictByIds list =
    list
        |> List.map (\item -> ( item.id, item ))
        |> Dict.fromList
